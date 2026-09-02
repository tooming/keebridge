"use strict";

const form = document.querySelector("#unlock-form");
const passwordInput = document.querySelector("#password");
const status = document.querySelector("#status");

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const password = passwordInput.value;
  passwordInput.value = "";
  if (!password) return;

  form.querySelector("button").disabled = true;
  status.textContent = "Unlocking…";
  try {
    const response = await browser.runtime.sendMessage({ action: "unlock", password });
    if (response?.ok) {
      status.textContent = "Unlocked. Return to the payment page and choose KeeBridge again.";
      form.remove();
    } else {
      status.textContent = "Could not unlock the vault. Check the password and try again.";
      form.querySelector("button").disabled = false;
      passwordInput.focus();
    }
  } catch {
    status.textContent = "KeeBridge's native card handler is unavailable.";
    form.querySelector("button").disabled = false;
  }
});
