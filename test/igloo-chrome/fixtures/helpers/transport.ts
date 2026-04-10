import type { BrowserContext, Page } from '@playwright/test';
import {
  COMMAND_TYPE,
  DEBUG_COMMAND_TYPE,
  type DiagnosticsGetMessage,
  type ExtensionCommand,
  type RuntimeDiagnosticsSnapshot,
  type RuntimeSnapshotInspection,
  type RuntimeStatusSnapshot,
  type ProfilesActivateMessage,
  type RuntimePrepareMessage,
} from '../../../../repos/igloo-chrome/src/extension/messages';
import {
  fetchRuntimeDiagnosticsFromPage,
  sendExtensionMessageFromPage,
} from '../../support/extension-status';
import { gotoExtensionPage } from './context';

export async function openPageForStorage(context: BrowserContext, extensionId: string) {
  const page = await context.newPage();
  await gotoExtensionPage(page, extensionId, 'options.html', { waitForAppReady: false });
  return page;
}

export async function sendExtensionMessageFromStoragePage<K extends ExtensionCommand['type']>(
  context: BrowserContext,
  extensionId: string,
  payload: Extract<ExtensionCommand, { type: K }>
) {
  const page = await openPageForStorage(context, extensionId);
  try {
    return await sendExtensionMessageFromPage(page, payload);
  } finally {
    await page.close().catch(() => undefined);
  }
}

export async function fetchRuntimeSnapshotViaExtension<T>(context: BrowserContext, extensionId: string) {
  const payload: DiagnosticsGetMessage = { type: COMMAND_TYPE.DIAGNOSTICS_GET };
  const status = await sendExtensionMessageFromStoragePage(context, extensionId, payload) as RuntimeDiagnosticsSnapshot;
  return {
    runtime: status.runtime,
    status: status.runtimeStatus?.status ?? null,
    snapshot: status.runtimeSnapshot ?? null,
    snapshotError: status.runtimeSnapshotError ?? null,
    runtimeLifecycle: status.runtimeLifecycle ?? null,
  } as T & RuntimeSnapshotInspection;
}

export async function fetchRuntimeStatusViaExtension<T>(context: BrowserContext, extensionId: string) {
  const payload: DiagnosticsGetMessage = { type: COMMAND_TYPE.DIAGNOSTICS_GET };
  const status = await sendExtensionMessageFromStoragePage(context, extensionId, payload) as RuntimeDiagnosticsSnapshot;
  return {
    runtime: status.runtime,
    status: status.runtimeStatus ?? null,
  } as T & RuntimeStatusSnapshot;
}

export async function fetchRuntimeDiagnosticsViaExtension<T>(context: BrowserContext, extensionId: string) {
  const payload: DiagnosticsGetMessage = { type: COMMAND_TYPE.DIAGNOSTICS_GET };
  return await sendExtensionMessageFromStoragePage(context, extensionId, payload) as T & RuntimeDiagnosticsSnapshot;
}

export async function sendRuntimePrepare<T>(
  context: BrowserContext,
  extensionId: string,
  operation: 'sign' | 'ecdh'
) {
  const payload: RuntimePrepareMessage = {
    type: COMMAND_TYPE.RUNTIME_PREPARE,
    operation,
  };
  return await sendExtensionMessageFromStoragePage(context, extensionId, payload) as T;
}

export async function activateProfileViaExtension(
  page: Page,
  profileId: string
) {
  const payload: ProfilesActivateMessage = {
    type: COMMAND_TYPE.PROFILES_ACTIVATE,
    profileId,
  };
  await page.evaluate(async (nextProfileId) => {
    const response = (await chrome.runtime.sendMessage(nextProfileId)) as
      | { ok?: boolean; error?: string }
      | undefined;
    if (!response?.ok) {
      throw new Error(response?.error || 'Profile activation failed');
    }
  }, payload);
}

export async function runRuntimeControlViaExtension(
  page: Page,
  action: 'stopRuntime' | 'reloadExtension'
) {
  const payload = {
    stopRuntime: { type: COMMAND_TYPE.RUNTIME_STOP },
    reloadExtension: { type: DEBUG_COMMAND_TYPE.RELOAD },
  }[action];
  await page.evaluate(async (nextAction) => {
    const response = (await chrome.runtime.sendMessage(nextAction)) as
      | { ok?: boolean; error?: string }
      | undefined;
    if (!response?.ok) {
      throw new Error(response?.error || 'Runtime control failed');
    }
  }, payload);
}

export async function reloadExtensionViaPage(page: Page) {
  const payload = { type: DEBUG_COMMAND_TYPE.RELOAD };
  await page.evaluate(async (messagePayload) => {
    const response = (await chrome.runtime.sendMessage(messagePayload)) as
      | { ok?: boolean; error?: string }
      | undefined;
    if (!response?.ok) {
      throw new Error(response?.error || 'Extension reload failed');
    }
  }, payload);
}

export async function fetchDiagnosticsFromPage<T>(page: Page) {
  return await fetchRuntimeDiagnosticsFromPage<T>(page);
}
