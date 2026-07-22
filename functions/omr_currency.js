"use strict";

const OMR_CURRENCY_CODE = "OMR";
const OMR_SYSTEM_LABEL = "ر.ع.";

function formatOmaniRialNumber(amountBaisa) {
  if (!Number.isSafeInteger(amountBaisa)) {
    throw new TypeError("amountBaisa must be a safe integer.");
  }
  const sign = amountBaisa < 0 ? "-" : "";
  const absolute = Math.abs(amountBaisa);
  return `${sign}${Math.floor(absolute / 1000)}.${String(absolute % 1000).padStart(3, "0")}`;
}

function formatOmaniRialForSystemNotification(amountBaisa) {
  return `${formatOmaniRialNumber(amountBaisa)} ${OMR_SYSTEM_LABEL}`;
}

function renderStructuredNotificationBody(notification) {
  if (!notification || notification.currencyCode !== OMR_CURRENCY_CODE ||
      !Number.isSafeInteger(notification.amountBaisa) ||
      typeof notification.bodyTemplate !== "string" ||
      !notification.bodyTemplate.includes("{amount}")) {
    return String(notification && notification.body || "");
  }
  return notification.bodyTemplate.replaceAll(
    "{amount}",
    formatOmaniRialForSystemNotification(notification.amountBaisa)
  ).replaceAll(`${OMR_SYSTEM_LABEL}.`, OMR_SYSTEM_LABEL);
}

module.exports = {
  OMR_CURRENCY_CODE,
  formatOmaniRialNumber,
  formatOmaniRialForSystemNotification,
  renderStructuredNotificationBody,
};
