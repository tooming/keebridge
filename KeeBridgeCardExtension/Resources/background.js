"use strict";

const nativeApplication = "com.martintooming.KeeBridge.CardExtension";
const allowedNativeActions = new Set(["listCards", "unlock", "fillCard"]);

browser.runtime.onMessage.addListener((message, sender) => {
  if (message?.action === "openUnlock") {
    return browser.tabs.create({ url: browser.runtime.getURL("unlock.html") })
      .then(() => ({ ok: true }));
  }
  if (!message || !allowedNativeActions.has(message.action)) {
    return Promise.resolve({ ok: false, status: "invalidRequest" });
  }
  if (message.action === "unlock" && sender.url !== browser.runtime.getURL("unlock.html")) {
    return Promise.resolve({ ok: false, status: "invalidRequest" });
  }
  return browser.runtime.sendNativeMessage(nativeApplication, message).catch(() => ({
    ok: false,
    status: "nativeUnavailable"
  }));
});
