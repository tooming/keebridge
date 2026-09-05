"use strict";

(() => {
  if (globalThis.__keeBridgeCardAutofillLoaded) return;
  globalThis.__keeBridgeCardAutofillLoaded = true;

  // manifest.json injects this script into every frame ("all_frames": true), so it
  // would otherwise also load inside a third-party iframe (an ad, a tracker, or worse
  // — an overlay deliberately styled to look like a card field). Card data has no
  // per-entry origin the way a login credential does (a card is legitimately reused
  // across many unrelated sites), so filtering *which cards* to show can't be the
  // fix here; the fix is not letting a frame the top-level page doesn't control run
  // the picker/fill flow at all. A same-origin iframe (e.g. a checkout widget hosted
  // on the same site) is trusted like the top-level page itself; a cross-origin
  // iframe is not, and this script exits before attaching anything — no trigger
  // button ever appears in it, so it can never reach listCards/fillCard.
  //
  // window.top is always readable by reference even cross-origin (only its
  // *properties*, like .location, are Same-Origin-Policy-restricted), so the
  // self-vs-top comparison is safe unconditionally; reading top.location.origin
  // throws precisely when top is a different origin, which the catch treats as
  // untrusted.
  const isTopLevelOrSameOriginFrame = (() => {
    if (window.self === window.top) return true;
    try {
      return window.top.location.origin === window.location.origin;
    } catch {
      return false;
    }
  })();
  if (!isTopLevelOrSameOriginFrame) return;

  const api = globalThis.browser;
  let activeField = null;
  let trigger = null;
  let panelHost = null;
  let pickerRoot = null;

  function fieldType(element) {
    if (!(element instanceof HTMLInputElement || element instanceof HTMLSelectElement)) return null;
    if (element.disabled || element.readOnly || element.type === "hidden") return null;

    const autocomplete = (element.autocomplete || "").toLowerCase().split(/\s+/).pop();
    const autocompleteTypes = {
      "cc-number": "number",
      "cc-name": "holder",
      "cc-exp": "expiration",
      "cc-exp-month": "expirationMonth",
      "cc-exp-year": "expirationYear",
      "cc-csc": "verificationCode"
    };
    if (autocompleteTypes[autocomplete]) return autocompleteTypes[autocomplete];

    const hint = [
      element.name, element.id, element.placeholder,
      element.getAttribute("aria-label"), element.getAttribute("title"),
      element.getAttribute("data-testid"),
      ...[...(element.labels || [])].map((label) => label.textContent)
    ].filter(Boolean).join(" ").toLowerCase().replace(/[_-]+/g, " ");

    if (/\b(cvv2?|cvc2?|cid)\b|(?:security|verification)\s*(?:code|number)|card\s*verification/.test(hint)) {
      return "verificationCode";
    }
    if (/(?:expir(?:y|ation)|\bexp\b|valid\s*(?:thru|through)).*(?:month|\bmm\b)|(?:month|\bmm\b).*(?:expir|\bexp\b)/.test(hint)) {
      return "expirationMonth";
    }
    if (/(?:expir(?:y|ation)|\bexp\b|valid\s*(?:thru|through)).*(?:year|\byy\b)|(?:year|\byy\b).*(?:expir|\bexp\b)/.test(hint)) {
      return "expirationYear";
    }
    if (/(?:expir(?:y|ation)|\bexp(?: date)?\b|valid\s*(?:thru|through))/.test(hint)) {
      return "expiration";
    }
    if (/(?:card|credit|cc)\s*(?:number|num|no)\b|(?:number|num)\s*(?:on\s*)?(?:card|credit)|\bpan\b/.test(hint)) {
      return "number";
    }
    if (/card\s*holder|cardholder|name\s*on\s*(?:the\s*)?card/.test(hint)) {
      return "holder";
    }
    return null;
  }

  function positionTrigger() {
    if (!trigger || !activeField || !activeField.isConnected) return hideTrigger();
    const rect = activeField.getBoundingClientRect();
    trigger.style.left = `${Math.max(4, rect.right - 30)}px`;
    trigger.style.top = `${Math.max(4, rect.top + (rect.height - 24) / 2)}px`;
  }

  function showTrigger(field) {
    activeField = field;
    if (!trigger) {
      trigger = document.createElement("button");
      trigger.type = "button";
      trigger.textContent = "▣";
      trigger.setAttribute("aria-label", "Fill payment card with KeeBridge");
      Object.assign(trigger.style, {
        position: "fixed", width: "24px", height: "24px", padding: "0",
        border: "1px solid #777", borderRadius: "5px", background: "#fff",
        color: "#222", cursor: "pointer", zIndex: "2147483646",
        font: "16px/22px system-ui"
      });
      trigger.addEventListener("mousedown", (event) => event.preventDefault());
      trigger.addEventListener("click", openPicker);
      document.documentElement.append(trigger);
    }
    trigger.hidden = false;
    positionTrigger();
  }

  function hideTrigger() {
    if (trigger) trigger.hidden = true;
    activeField = null;
  }

  function detectedFields(root = document) {
    const result = new Map();
    root.querySelectorAll("input, select").forEach((element) => {
      const type = fieldType(element);
      if (type) {
        if (!result.has(type)) result.set(type, []);
        result.get(type).push(element);
      }
    });
    return result;
  }

  async function nativeRequest(request) {
    return api.runtime.sendMessage({ ...request, origin: location.origin });
  }

  function createPanel() {
    closePanel();
    panelHost = document.createElement("div");
    Object.assign(panelHost.style, {
      position: "fixed", inset: "0", zIndex: "2147483647", pointerEvents: "none"
    });
    const shadow = panelHost.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = `
      .panel { pointer-events:auto; position:absolute; top:50%; left:50%; transform:translate(-50%,-50%);
        width:min(360px,calc(100vw - 32px)); max-height:70vh; overflow:auto; padding:16px;
        box-sizing:border-box; border:1px solid #888; border-radius:12px; background:#fff; color:#171717;
        box-shadow:0 12px 44px #0006; font:14px system-ui; }
      h2 { font-size:17px; margin:0 28px 12px 0; } p { color:#555; }
      button { display:block; width:100%; margin:8px 0; padding:10px; text-align:left; cursor:pointer;
        border:1px solid #aaa; border-radius:7px; background:#f7f7f7; color:#171717; font:inherit; }
      .close { position:absolute; right:10px; top:5px; width:auto; border:0; background:none; font-size:22px; }
      input { width:100%; padding:9px; box-sizing:border-box; border:1px solid #888; border-radius:6px; }
    `;
    const panel = document.createElement("div");
    panel.className = "panel";
    const close = document.createElement("button");
    close.className = "close";
    close.textContent = "×";
    close.setAttribute("aria-label", "Close");
    close.addEventListener("click", closePanel);
    panel.append(close);
    shadow.append(style, panel);
    document.documentElement.append(panelHost);
    return panel;
  }

  function closePanel() {
    panelHost?.remove();
    panelHost = null;
    pickerRoot = null;
  }

  function message(panel, text) {
    const p = document.createElement("p");
    p.textContent = text;
    panel.append(p);
  }

  function renderUnlock(panel) {
    panel.replaceChildren(panel.querySelector(".close"));
    const heading = document.createElement("h2");
    heading.textContent = "Unlock KeeBridge cards";
    const unlock = document.createElement("button");
    unlock.textContent = "Open secure unlock page";
    unlock.addEventListener("click", async () => {
      unlock.disabled = true;
      const response = await nativeRequest({ action: "openUnlock" });
      if (response?.ok) {
        closePanel();
      } else {
        unlock.disabled = false;
        message(panel, "Could not open the secure unlock page.");
      }
    });
    panel.append(heading);
    message(panel, "The vault password is entered on a Safari extension page, never inside this website.");
    panel.append(unlock);
  }

  function renderCards(panel, cards) {
    panel.replaceChildren(panel.querySelector(".close"));
    const heading = document.createElement("h2");
    heading.textContent = "Choose a card";
    panel.append(heading);
    if (!cards.length) {
      message(panel, "No entries with recognized card fields were found.");
      return;
    }
    cards.forEach((card) => {
      const button = document.createElement("button");
      button.textContent = card.title || "Untitled card";
      button.addEventListener("click", () => fillCard(card.id, panel, button));
      panel.append(button);
    });
  }

  async function openPicker() {
    const panel = createPanel();
    pickerRoot = activeField?.form || document;
    const heading = document.createElement("h2");
    heading.textContent = "KeeBridge cards";
    panel.append(heading);
    message(panel, "Loading…");
    const response = await nativeRequest({ action: "listCards" });
    if (response?.ok) renderCards(panel, response.cards || []);
    else if (response?.status === "locked") renderUnlock(panel);
    else if (response?.status === "missingMirror") {
      panel.replaceChildren(panel.querySelector(".close"));
      message(panel, "Open KeeBridge and unlock or refresh your vault first.");
    } else {
      panel.replaceChildren(panel.querySelector(".close"));
      message(panel, "KeeBridge Card AutoFill is unavailable.");
    }
  }

  async function fillCard(cardID, panel, button) {
    const fields = detectedFields(pickerRoot || document);
    const requested = [...fields.keys()];
    button.disabled = true;
    const response = await nativeRequest({ action: "fillCard", cardID, fields: requested });
    if (!response?.ok) {
      button.disabled = false;
      message(panel, "Could not read that card.");
      return;
    }
    const values = response.values || {};
    for (const [type, elements] of fields) {
      if (typeof values[type] !== "string") continue;
      elements.forEach((element) => setFieldValue(element, formatValue(type, values[type], element)));
      values[type] = "";
    }
    closePanel();
  }

  function formatValue(type, value, element) {
    if (type === "number" || type === "verificationCode") return value.replace(/\D/g, "");
    if (type === "expirationMonth") {
      const digits = value.replace(/\D/g, "").padStart(2, "0").slice(-2);
      if (element instanceof HTMLSelectElement) {
        return [...element.options].find((option) =>
          Number(option.value.replace(/\D/g, "")) === Number(digits)
        )?.value || digits;
      }
      return digits;
    }
    if (type === "expirationYear") {
      const digits = value.replace(/\D/g, "");
      if (element instanceof HTMLSelectElement) {
        return [...element.options].find((option) => {
          const optionDigits = option.value.replace(/\D/g, "");
          return optionDigits && optionDigits.slice(-2) === digits.slice(-2);
        })?.value || digits;
      }
      const optionsUseTwoDigits = element instanceof HTMLSelectElement &&
        [...element.options].some((option) => /^\d{2}$/.test(option.value));
      return optionsUseTwoDigits ? digits.slice(-2) : (digits.length === 2 ? `20${digits}` : digits);
    }
    if (type === "expiration") {
      const parts = value.match(/(\d{1,4})\D+(\d{1,4})/);
      if (parts) {
        const yearFirst = parts[1].length === 4;
        const year = yearFirst ? parts[1] : (parts[2].length === 2 ? `20${parts[2]}` : parts[2]);
        const month = (yearFirst ? parts[2] : parts[1]).padStart(2, "0");
        if (element instanceof HTMLInputElement && element.type === "month") return `${year}-${month}`;
        const placeholder = (element.getAttribute("placeholder") || "").toLowerCase();
        if (element.maxLength === 4) return `${month}${year.slice(-2)}`;
        if (element.maxLength === 6 && !placeholder.includes("/")) return `${month}${year}`;
        const yyyyIndex = placeholder.indexOf("yyyy");
        if (yyyyIndex !== -1) {
          // Match the placeholder's own token order and separator instead of
          // assuming "MM/YYYY": a "yyyy" substring alone doesn't tell us
          // whether the placeholder is month-first ("MM/YYYY") or year-first
          // ("YYYY-MM", "YYYY/MM"), nor which separator it uses. Getting
          // either wrong silently writes objectively incorrect data into a
          // field that validates against its own stated format (e.g. "04/2027"
          // into a "YYYY-MM" field is the wrong order AND the wrong separator,
          // not just a different style).
          const mmIndex = placeholder.indexOf("mm");
          const placeholderYearFirst = mmIndex === -1 || yyyyIndex < mmIndex;
          const separator = placeholder.includes("-") ? "-" : "/";
          return placeholderYearFirst ? `${year}${separator}${month}` : `${month}${separator}${year}`;
        }
        return `${month}/${year.slice(-2)}`;
      }
    }
    return value;
  }

  function setFieldValue(element, value) {
    const prototype = element instanceof HTMLSelectElement
      ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
    if (setter) setter.call(element, value);
    else element.value = value;
    element.dispatchEvent(new Event("input", { bubbles: true }));
    element.dispatchEvent(new Event("change", { bubbles: true }));
  }

  document.addEventListener("focusin", (event) => {
    if (fieldType(event.target)) showTrigger(event.target);
  }, true);
  document.addEventListener("focusout", () => {
    setTimeout(() => {
      if (document.activeElement !== trigger && !fieldType(document.activeElement)) hideTrigger();
    }, 0);
  }, true);
  addEventListener("scroll", positionTrigger, true);
  addEventListener("resize", positionTrigger);
})();
