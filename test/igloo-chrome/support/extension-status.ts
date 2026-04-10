import type { Page } from '@playwright/test';
import {
  COMMAND_TYPE,
  type DiagnosticsGetMessage,
  type ExtensionCommand,
  type ExtensionCommandResult,
  type ExtensionMessageResponse,
  type StateGetMessage,
} from '../../../repos/igloo-chrome/src/extension/messages';

const DEFAULT_EXTENSION_MESSAGE_TIMEOUT_MS = 1_500;

export async function sendExtensionMessageFromPage<T extends ExtensionCommand['type']>(
  page: Page,
  payload: Extract<ExtensionCommand, { type: T }>,
  timeoutMs = DEFAULT_EXTENSION_MESSAGE_TIMEOUT_MS
): Promise<ExtensionCommandResult<T>> {
  return await page.evaluate(
    async ({ messagePayload, messageTimeoutMs }) => {
      const response = (await Promise.race([
        chrome.runtime.sendMessage(messagePayload),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error(`extension message timed out: ${String(messagePayload.type)}`)), messageTimeoutMs)
        )
      ])) as ExtensionMessageResponse<unknown> | undefined;

      if (!response?.ok) {
        throw new Error(response?.error || 'Extension message failed');
      }

      return response.result;
    },
    {
      messagePayload: payload,
      messageTimeoutMs: timeoutMs
    }
  ) as Promise<ExtensionCommandResult<T>>;
}

export async function fetchExtensionAppStateFromPage<T>(page: Page): Promise<T> {
  const payload: StateGetMessage = {
    type: COMMAND_TYPE.STATE_GET
  };
  return await sendExtensionMessageFromPage(page, payload) as T;
}

export async function fetchRuntimeDiagnosticsFromPage<T>(page: Page): Promise<T> {
  const payload: DiagnosticsGetMessage = {
    type: COMMAND_TYPE.DIAGNOSTICS_GET
  };
  return await sendExtensionMessageFromPage(page, payload) as T;
}

export async function fetchRuntimeSnapshotFromPage<T>(page: Page): Promise<T> {
  const payload: DiagnosticsGetMessage = {
    type: COMMAND_TYPE.DIAGNOSTICS_GET
  };
  return await sendExtensionMessageFromPage(page, payload) as T;
}

export async function fetchRuntimeStatusFromPage<T>(page: Page): Promise<T> {
  const payload: DiagnosticsGetMessage = {
    type: COMMAND_TYPE.DIAGNOSTICS_GET
  };
  return await sendExtensionMessageFromPage(page, payload) as T;
}

export async function fetchWorkerStorageSnapshot(page: Page) {
  return await page.evaluate(async () => {
    const chromeStorage =
      typeof chrome !== 'undefined' && chrome.storage?.local
        ? await chrome.storage.local.get(null)
        : null;
    const chromeSession =
      typeof chrome !== 'undefined' && chrome.storage?.session
        ? await chrome.storage.session.get(null)
        : null;
    return {
      chromeStorage,
      chromeSession,
      href: window.location.href,
      bodyText: (document.body?.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 1_500)
    };
  });
}
