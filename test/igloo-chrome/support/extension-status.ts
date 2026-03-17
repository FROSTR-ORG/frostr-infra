import type { Page } from '@playwright/test';

const DEFAULT_EXTENSION_MESSAGE_TIMEOUT_MS = 1_500;

async function sendExtensionMessage<T>(
  page: Page,
  payload: Record<string, unknown>,
  timeoutMs = DEFAULT_EXTENSION_MESSAGE_TIMEOUT_MS
): Promise<T> {
  return await page.evaluate(
    async ({ messagePayload, messageTimeoutMs }) => {
      const response = (await Promise.race([
        chrome.runtime.sendMessage(messagePayload),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error(`extension message timed out: ${String(messagePayload.type)}`)), messageTimeoutMs)
        )
      ])) as { ok?: boolean; result?: unknown; error?: string } | undefined;

      if (!response?.ok || response.result === undefined) {
        throw new Error(response?.error || 'Extension message failed');
      }

      return response.result;
    },
    {
      messagePayload: payload,
      messageTimeoutMs: timeoutMs
    }
  ) as Promise<T>;
}

export async function fetchExtensionStatusFromPage<T>(page: Page): Promise<T> {
  return await sendExtensionMessage<T>(page, {
    type: 'ext.getStatus'
  });
}

export async function fetchExtensionAppStateFromPage<T>(page: Page): Promise<T> {
  return await sendExtensionMessage<T>(page, {
    type: 'ext.getAppState'
  });
}

export async function fetchRuntimeDiagnosticsFromPage<T>(page: Page): Promise<T> {
  return await sendExtensionMessage<T>(page, {
    type: 'ext.getRuntimeDiagnostics'
  });
}

export async function fetchWorkerStorageSnapshot(page: Page) {
  return await page.evaluate(() => ({
    profileRaw: window.localStorage.getItem('igloo.v2.profile'),
    runtimeSnapshotRaw: window.localStorage.getItem('igloo.ext.runtimeSnapshot'),
    profilePresent: !!window.localStorage.getItem('igloo.v2.profile'),
    runtimeSnapshotPresent: !!window.localStorage.getItem('igloo.ext.runtimeSnapshot'),
    href: window.location.href,
    bodyText: (document.body?.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 1_500)
  }));
}
