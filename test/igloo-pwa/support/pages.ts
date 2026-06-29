import { expect, type Locator, type Page } from '@playwright/test';
import { LIVE_EXPECT_TIMEOUT_MS } from '../../shared/playwright-config';

import { TID, type CriticalE2ETestId } from './ui';

// Screen-scoped page objects for the igloo-pwa Playwright suite. Specs drive the
// app through these (never raw text/role/label/class locators), so UI copy and
// markup changes don't ripple into specs. Test-ids come from the central
// registry via support/ui.ts (the only allowed registry importer).

class BasePage {
  constructor(protected readonly page: Page) {}
  protected tid(id: CriticalE2ETestId): Locator {
    return this.page.getByTestId(id);
  }
}

export class WelcomePage extends BasePage {
  async goto(): Promise<void> {
    await this.page.goto('/');
  }
  async expectEntryHero(): Promise<void> {
    await expect(this.tid(TID.welcomeEntryGenerate)).toBeVisible();
  }
  async expectReturning(count?: number): Promise<void> {
    await expect(this.tid(TID.welcomeProfileRow).first()).toBeVisible();
    if (count != null) await expect(this.tid(TID.welcomeProfileRow)).toHaveCount(count);
  }
  row(profileId?: string): Locator {
    return profileId
      ? this.page.locator(`[data-testid="${TID.welcomeProfileRow}"][data-profile-id="${profileId}"]`)
      : this.tid(TID.welcomeProfileRow).first();
  }
  async startGenerate(): Promise<void> {
    await this.tid(TID.welcomeEntryGenerate).click();
  }
  async startImport(): Promise<void> {
    await this.tid(TID.welcomeEntryImport).click();
  }
  async startOnboard(): Promise<void> {
    await this.tid(TID.welcomeEntryOnboard).click();
  }
  rowCount(): Locator {
    return this.tid(TID.welcomeProfileRow);
  }
  async expectRowCount(count: number): Promise<void> {
    await expect(this.tid(TID.welcomeProfileRow)).toHaveCount(count);
  }
  async openUnlock(profileId?: string): Promise<void> {
    await this.row(profileId).getByTestId(TID.welcomeProfileUnlock).click();
  }
  async fillUnlockPassword(password: string): Promise<void> {
    await this.tid(TID.welcomeUnlockPassword).fill(password);
  }
  async submitUnlock(): Promise<void> {
    await this.tid(TID.welcomeUnlockSubmit).click();
  }
  async unlock(password: string, profileId?: string): Promise<void> {
    await this.openUnlock(profileId);
    await this.fillUnlockPassword(password);
    await this.submitUnlock();
  }
  async openMenu(profileId?: string): Promise<void> {
    await this.row(profileId).getByTestId(TID.welcomeProfileMenuTrigger).click();
  }
  async expectMenuOpen(): Promise<void> {
    await expect(this.tid(TID.welcomeProfileMenuRecover)).toBeVisible();
  }
  async rotate(profileId?: string): Promise<void> {
    await this.openMenu(profileId);
    await this.tid(TID.welcomeProfileMenuRotate).click();
  }
  async recover(profileId?: string): Promise<void> {
    await this.openMenu(profileId);
    await this.tid(TID.welcomeProfileMenuRecover).click();
  }
  async delete(profileId?: string): Promise<void> {
    await this.openMenu(profileId);
    await this.tid(TID.welcomeProfileMenuDelete).click();
  }
}

export class CreateFlowPage extends BasePage {
  async selectMode(mode: 'new' | 'rotate'): Promise<void> {
    await this.tid(mode === 'new' ? TID.createModeNew : TID.createModeRotate).click();
  }
  async selectRotateSource(profileId: string): Promise<void> {
    await this.tid(TID.rotateSourceProfile).selectOption(profileId);
  }
  async unlockRotateLocalShare(password: string): Promise<void> {
    await this.tid(TID.rotateLocalPassphrase).fill(password);
    await expect(this.tid(TID.rotateLocalPassphraseSubmit)).toBeEnabled();
    await this.tid(TID.rotateLocalPassphraseSubmit).click();
    await expect(this.page.getByRole('group', { name: /this device.*Ready/i })).toBeVisible();
  }
  // Per-source rows are dynamic; labels are stable while placeholder copy can
  // change as the accepted package formats evolve.
  async fillRotateSource(index: number, opts: { bfshare: string; password: string }): Promise<void> {
    await this.page.getByLabel('Source Package').nth(index).fill(opts.bfshare);
    await this.page.getByLabel('Package Password').nth(index).fill(opts.password);
  }
  async addRotateSource(): Promise<void> {
    await this.tid(TID.rotateAddSource).click();
  }
  async rotateSubmit(): Promise<void> {
    await this.tid(TID.rotateSubmit).click();
  }
  async fillGenerate(opts: { groupName?: string; privateKey?: string }): Promise<void> {
    if (opts.groupName != null) await this.page.getByLabel('Group Name').fill(opts.groupName);
    if (opts.privateKey != null) {
      await this.page.getByLabel('Existing Private Key (optional)').fill(opts.privateKey);
    }
  }
  get generateNextButton(): Locator {
    return this.tid(TID.createGenerateNext);
  }
  get backButton(): Locator {
    return this.tid(TID.createBack);
  }
  async generateNext(): Promise<void> {
    await this.tid(TID.createGenerateNext).click();
  }
  async back(): Promise<void> {
    await this.tid(TID.createBack).click();
  }
  async copyGroupKey(): Promise<void> {
    await this.tid(TID.selectShareCopyGroupKey).click();
  }
  shareOption(memberIdx: number): Locator {
    return this.page.locator(`[data-testid="${TID.selectShareOption}"][data-member-idx="${memberIdx}"]`);
  }
  async selectShare(memberIdx: number): Promise<void> {
    await this.shareOption(memberIdx).click();
  }
  async selectShareByName(name: string): Promise<void> {
    await this.tid(TID.selectShareOption).filter({ hasText: name }).click();
  }
  async selectShareNext(): Promise<void> {
    await this.tid(TID.selectShareNext).click();
  }
  async fillSaveProfile(opts: { name?: string; password: string; confirm?: string }): Promise<void> {
    if (opts.name != null) await this.tid(TID.saveProfileName).fill(opts.name);
    await this.tid(TID.saveProfilePassword).fill(opts.password);
    await this.tid(TID.saveProfileConfirm).fill(opts.confirm ?? opts.password);
  }
  async saveProfileNext(): Promise<void> {
    await this.tid(TID.saveProfileNext).click();
  }
  relayRow(url: string): Locator {
    return this.page.locator(`[data-testid="${TID.relayRow}"][data-relay-url="${url}"]`);
  }
  async expectRelay(url: string): Promise<void> {
    await expect(this.relayRow(url)).toBeVisible();
  }
  async addRelay(url: string): Promise<void> {
    await this.tid(TID.relayAddInput).fill(url);
    await this.tid(TID.relayAddSubmit).click();
  }
}

export class DistributePage extends BasePage {
  cards(): Locator {
    return this.tid(TID.distributionCard);
  }
  card(memberIdx: number): Locator {
    return this.page.locator(`[data-testid="${TID.distributionCard}"][data-member-idx="${memberIdx}"]`);
  }
  cardByName(name: string): Locator {
    return this.cards().filter({ hasText: name }).first();
  }
  async readQrPackage(): Promise<string> {
    // The redesigned QR modal (QrPayloadModal) renders the package in a masked
    // SensitiveTextarea instead of a <pre class="igloo-code-block">. Reveal it,
    // then read the underlying textarea value (inputValue, not textContent).
    const dialog = this.page.getByRole('dialog');
    const reveal = dialog.getByRole('button', { name: 'Reveal' });
    if (await reveal.isVisible().catch(() => false)) {
      await reveal.click();
    }
    const textarea = dialog.locator('textarea');
    await textarea.waitFor({ state: 'visible' });
    return (await textarea.inputValue()).trim();
  }
  async closeQr(): Promise<void> {
    await this.page.keyboard.press('Escape');
  }
  async cardStatus(card: Locator): Promise<string | null> {
    return card.getAttribute('data-status');
  }
  async preparePackage(card: Locator, password: string): Promise<void> {
    await card.getByTestId(TID.distributionPackagePassword).fill(password);
    await card.getByTestId(TID.distributionPrepare).click();
  }
  async copy(card: Locator): Promise<void> {
    await card.getByTestId(TID.distributionCopy).click();
  }
  async save(card: Locator): Promise<void> {
    await card.getByTestId(TID.distributionSave).click();
  }
  async showQr(card: Locator): Promise<void> {
    await card.getByTestId(TID.distributionQr).click();
  }
  async markDelivered(card: Locator): Promise<void> {
    await card.getByTestId(TID.distributionMark).click();
  }
  async cancel(card: Locator): Promise<void> {
    await card.getByTestId(TID.distributionCancel).click();
  }
  async revert(card: Locator): Promise<void> {
    await card.getByTestId(TID.distributionRevert).click();
  }
  async finish(): Promise<void> {
    await this.tid(TID.distributionFinish).click();
  }
}

export class OnboardPage extends BasePage {
  async connect(opts: { packageText: string; password: string }): Promise<void> {
    await this.tid(TID.onboardPackageInput).fill(opts.packageText);
    await this.tid(TID.onboardPasswordInput).fill(opts.password);
    await this.submitConnect();
  }
  async submitConnect(): Promise<void> {
    await this.tid(TID.onboardConnectSubmit).click();
  }
  async save(opts: { name?: string; password: string }): Promise<void> {
    if (opts.name != null) await this.tid(TID.onboardSaveName).fill(opts.name);
    await this.tid(TID.onboardSavePassword).fill(opts.password);
    await this.tid(TID.onboardSaveConfirm).fill(opts.password);
    await this.tid(TID.onboardSaveSubmit).click();
  }
}

export class ImportPage extends BasePage {
  async submit(opts: { profileString: string; password: string }): Promise<void> {
    await this.tid(TID.importProfileInput).fill(opts.profileString);
    await this.tid(TID.importPasswordInput).fill(opts.password);
    await this.next();
  }
  async next(): Promise<void> {
    await this.tid(TID.importNext).click();
  }
}

export class RecoverPage extends BasePage {
  // Collect-shares step. The local device contributes its own share, unlocked with
  // its passphrase, toward the threshold.
  async fillDevicePassphrase(passphrase: string): Promise<void> {
    await this.tid(TID.recoverDevicePassphrase).fill(passphrase);
  }
  // Source rows are dynamic; located by placeholder/label within the panel (raw
  // locators are allowed inside support, not in specs).
  async fillSource(index: number, opts: { packageText: string; password: string }): Promise<void> {
    await this.page
      .getByPlaceholder('Paste bfprofile or bfshare from another device or backup...')
      .nth(index)
      .fill(opts.packageText);
    await this.page.getByLabel('Package Password').nth(index).fill(opts.password);
  }
  async addSource(): Promise<void> {
    await this.page.getByRole('button', { name: 'Add Source' }).click();
  }
  async next(): Promise<void> {
    await this.tid(TID.recoverNext).click();
  }
  // Recover-key success step. The reconstructed nsec is masked until revealed.
  async expectRecovered(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Recover Private Key' })).toBeVisible({ timeout: 30_000 });
  }
  async revealKey(): Promise<void> {
    await this.tid(TID.recoverRevealKey).click();
  }
  async readRecoveredKey(): Promise<string> {
    return ((await this.tid(TID.recoverKeyValue).textContent()) ?? '').trim();
  }
}

export type DashboardBannerKind = 'signing-blocked' | 'all-relays-offline' | 'signing-failed';

export class DashboardPage extends BasePage {
  // `_profileLabel` is accepted for call-site readability but not asserted: the
  // Paper-redesigned pwa dashboard no longer renders the device label anywhere
  // (dashboard-root holds only the signer panel). The correct profile is already
  // guaranteed upstream by the load/create flow. (See expectPwaDashboard in ui.ts.)
  async expectDashboard(_profileLabel?: string): Promise<void> {
    await expect(this.tid(TID.dashboardRoot)).toBeVisible();
    await expect(this.tid(TID.dashboardTabSigner)).toBeVisible();
  }
  async openTab(tab: 'signer' | 'permissions' | 'settings'): Promise<void> {
    const id =
      tab === 'signer'
        ? TID.dashboardTabSigner
        : tab === 'permissions'
          ? TID.dashboardTabPermissions
          : TID.dashboardTabSettings;
    const tabButton = this.tid(id);
    if ((await tabButton.getAttribute('aria-pressed')) === 'true') return;
    await tabButton.click();
  }
  async closeSettings(): Promise<void> {
    await this.tid(TID.dashboardSettingsSidebarClose).click();
  }
  // Dashboard conditions render with a `dashboard-banner-<kind>` test id, even
  // when a severe condition is promoted into the Paper-style unavailable panel.
  // The id is composed dynamically, so it isn't a static TID-registry entry; the
  // locator lives here in the page object (specs route through these helpers).
  conditionBanner(kind: DashboardBannerKind): Locator {
    return this.page.getByTestId(`dashboard-banner-${kind}`);
  }
  async expectConditionBanner(kind: DashboardBannerKind, opts?: { timeout?: number }): Promise<void> {
    await expect(this.conditionBanner(kind)).toBeVisible({ timeout: opts?.timeout });
  }
  async expectNoConditionBanner(kind: DashboardBannerKind): Promise<void> {
    await expect(this.conditionBanner(kind)).toHaveCount(0);
  }
  async expectRecoverCollect(returnTarget: 'dashboard' | 'welcome' = 'dashboard'): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Collect Shares' })).toBeVisible();
    await expect(
      this.page.getByText(returnTarget === 'dashboard' ? 'Back to Dashboard' : 'Back to Welcome'),
    ).toBeVisible();
    if (returnTarget === 'dashboard') {
      await this.expectNavLinks();
    }
  }
  async fillRecoverSource(index: number, opts: { sourcePackage: string; password: string }): Promise<void> {
    await this.page.getByLabel('Source Package').nth(index).fill(opts.sourcePackage);
    await this.page.getByLabel('Package Password').nth(index).fill(opts.password);
  }
  async recoverNext(): Promise<void> {
    await this.page.getByRole('button', { name: 'Next Step' }).click();
  }
  async expectRecoveredPrivateKey(nsec: string): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Recover Private Key' })).toBeVisible({ timeout: 30_000 });
    await this.page.getByRole('button', { name: 'Reveal' }).click();
    await expect(this.page.getByText(nsec, { exact: true })).toBeVisible();
  }
  async encryptRecoveredPrivateKey(password: string): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Recover Private Key' })).toBeVisible({ timeout: 30_000 });
    await this.page.getByLabel(/Encrypt Key/i).check();
    await this.page.getByRole('textbox', { name: 'Password Show password', exact: true }).fill(password);
    await this.page.getByRole('textbox', { name: 'Confirm Password Show password' }).fill(password);
    await expect(this.page.getByText(/^ncryptsec1/)).toBeVisible();
  }
  async backFromRecover(returnTarget: 'dashboard' | 'welcome' = 'dashboard'): Promise<void> {
    await this.page.getByText(returnTarget === 'dashboard' ? 'Back to Dashboard' : 'Back to Welcome').click();
  }
  async expectNoRecoverSuccess(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Recover Private Key' })).toHaveCount(0);
  }
  get autoOpenToggle(): Locator {
    return this.tid(TID.settingsAutoOpenToggle);
  }
  async expectSettingsActions(): Promise<void> {
    await expect(this.tid(TID.settingsCopyProfile)).toBeVisible();
    await expect(this.tid(TID.settingsCopyShare)).toBeVisible();
    await expect(this.tid(TID.maintenanceRotateShare)).toBeVisible();
    await expect(this.tid(TID.settingsLogout)).toBeVisible();
  }
  async logout(): Promise<void> {
    await this.tid(TID.settingsLogout).click();
  }
  // Merged identity/runtime card (Phase B dashboard redesign).
  async expectNavLinks(): Promise<void> {
    await expect(this.tid(TID.dashboardTabSigner)).toBeVisible();
    await expect(this.tid(TID.dashboardTabPermissions)).toBeVisible();
    await expect(this.tid(TID.dashboardTabSettings)).toBeVisible();
  }
  async expectKeyDisplays(groupDisplay: string, shareDisplay: string): Promise<void> {
    await expect(this.page.getByText(groupDisplay)).toBeVisible();
    await expect(this.page.getByText(shareDisplay)).toBeVisible();
  }
  async expectKeyCopyControls(): Promise<void> {
    await expect(this.tid(TID.dashboardGroupKeyCopy)).toBeVisible();
    await expect(this.tid(TID.dashboardShareKeyCopy)).toBeVisible();
  }
  async expectPendingApprovalsEmpty(): Promise<void> {
    await expect(this.tid(TID.dashboardPendingApprovals)).toContainText('No pending approvals');
  }
  // Stopped-state signer dashboard (Paper: 2-stopped): the runtime snapshot is
  // in-memory only and never persisted, so a storage-seeded dashboard renders
  // the stopped layout with the Readiness + Next Step cards.
  async expectStopped(): Promise<void> {
    await expect(this.tid(TID.dashboardRoot)).toContainText('Start signer to restore connectivity.');
    await expect(this.tid(TID.dashboardRoot)).toContainText('Start when ready.');
  }
  // --- Pending Approvals card (the `ask` disposition) --------------------
  // The decision buttons render test-ids composed off the registered
  // dashboard-pending-approvals base; build raw locators like peerPolicyToggle
  // (only registered ids are accepted by tid()). The spec parks one request at
  // a time, so each button locator resolves to exactly one element.
  private pendingApprovalButton(action: 'deny' | 'allow-once' | 'always-allow'): Locator {
    return this.page.locator(`[data-testid="${TID.dashboardPendingApprovals}-${action}"]`);
  }
  async expectPendingApprovalVisible(timeout = 30_000): Promise<void> {
    await expect(this.pendingApprovalButton('allow-once')).toBeVisible({ timeout });
  }
  async denyPendingApproval(): Promise<void> {
    await this.pendingApprovalButton('deny').click();
  }
  async approvePendingApprovalOnce(): Promise<void> {
    await this.pendingApprovalButton('allow-once').click();
  }
  async alwaysAllowPendingApproval(): Promise<void> {
    await this.pendingApprovalButton('always-allow').click();
  }
  // Permissions page (peer-only on the PWA; the site/origin section is chrome-only).
  async expectPeerPermissions(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Peer Permissions' })).toBeVisible();
  }
  async expectNoSignerPermissions(): Promise<void> {
    // The PWA signer has no website/origin permissions, so that section must not render.
    await expect(this.page.getByRole('heading', { name: 'Signer Permissions' })).toHaveCount(0);
  }
  // Settings page (Paper-aligned section layout).
  async expectSettingsSections(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Device Profile', exact: true })).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Replace Share', exact: true }).first()).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Export Profile', exact: true }).first()).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Export Share', exact: true }).first()).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Logout', exact: true }).first()).toBeVisible();
  }
  // Export package modal (Phase B step 4).
  async openExportProfile(): Promise<void> {
    await this.tid(TID.settingsCopyProfile).click();
  }
  async expectExportModalEntry(): Promise<void> {
    await expect(this.tid(TID.exportPassword)).toBeVisible();
    await expect(this.tid(TID.exportConfirm)).toBeVisible();
    await expect(this.tid(TID.exportSubmit)).toBeVisible();
  }
  async closeExportModalEntry(): Promise<void> {
    await this.page.getByRole('dialog').getByRole('button', { name: 'Cancel' }).click();
    await expect(this.tid(TID.exportPassword)).toHaveCount(0);
  }
  // Makes the Settings form dirty by editing the signer name (Device Profile).
  async editSignerName(value: string): Promise<void> {
    await this.page.getByPlaceholder('Unnamed signer').fill(value);
  }
  // Unsaved-changes guard modal (leaving Settings with edits).
  async expectUnsavedGuard(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Discard unsaved changes?' })).toBeVisible();
  }
  async keepEditing(): Promise<void> {
    await this.page.getByRole('button', { name: 'Keep editing' }).click();
  }
  async discardChanges(): Promise<void> {
    await this.page.getByRole('button', { name: 'Discard' }).click();
  }
  async openClearCredentialsDialog(): Promise<void> {
    const clearButton = this.tid(TID.settingsClearCredentials);
    await clearButton.scrollIntoViewIfNeeded();
    await clearButton.click();
  }
  async expectClearCredentialsDialog(): Promise<void> {
    await expect(this.page.getByRole('dialog', { name: 'Clear Credentials' })).toBeVisible();
  }
  // Drives the export modal to completion and returns the re-encrypted package text.
  async exportProfileWithPassword(password: string): Promise<string> {
    await this.openExportProfile();
    await this.expectExportModalEntry();
    const passwordField = this.tid(TID.exportPassword);
    const confirm = this.tid(TID.exportConfirm);
    // The Export button enables only once both fields match. Under back-to-back-run
    // CPU contention the ExportPackageModal's controlled-input onChange can lag well
    // past the default 10s expect timeout, so a single fill + toHaveValue flakes.
    // Re-fill both fields and poll the confirm value at the live timeout until it
    // lands, then wait for the button to enable before clicking.
    await expect
      .poll(
        async () => {
          await passwordField.fill(password);
          await confirm.fill(password);
          return confirm.inputValue();
        },
        { timeout: LIVE_EXPECT_TIMEOUT_MS, intervals: [100, 250, 500, 1000] },
      )
      .toBe(password);
    const submit = this.tid(TID.exportSubmit);
    await expect(submit).toBeEnabled({ timeout: LIVE_EXPECT_TIMEOUT_MS });
    await submit.click();
    const result = this.tid(TID.exportResult);
    await expect(result).toBeVisible({ timeout: 30_000 });
    return (await result.textContent()) ?? '';
  }

  // --- Permissions tab: peer policy editor -------------------------------
  // Each peer row exposes one toggle per direction × method (and per peer when
  // multiple peers are present). The pubkey filter is optional — omit it when
  // there is exactly one peer and the (direction, method) pair is unambiguous.
  peerPolicyToggle(opts: PeerPolicySelector): Locator {
    const parts = [
      `[data-testid="${TID.permissionToggle}"]`,
      `[data-direction="${opts.direction}"]`,
      `[data-method="${opts.method}"]`,
    ];
    if (opts.pubkey) parts.push(`[data-peer-pubkey="${opts.pubkey}"]`);
    return this.page.locator(parts.join(''));
  }
  async expectPeerPolicyVisible(opts: PeerPolicySelector, timeout = 45_000): Promise<void> {
    await expect(this.peerPolicyToggle(opts)).toBeVisible({ timeout });
  }
  async togglePeerPolicy(opts: PeerPolicySelector): Promise<void> {
    await this.peerPolicyToggle(opts).click();
  }
  // Asserts the toggle's live EFFECTIVE value (data-allowed mirrors the negotiated
  // policy capability).
  async expectPeerPolicyAllowed(opts: PeerPolicySelector, allowed: boolean): Promise<void> {
    await expect(this.peerPolicyToggle(opts)).toHaveAttribute('data-allowed', allowed ? 'true' : 'false');
  }
  // Asserts the operator's MANUAL override (data-override) — the directly-edited,
  // persisted tri-state. This is what a toggle click mutates and what survives a
  // reload, independent of the negotiated effective capability.
  async expectPeerPolicyOverride(opts: PeerPolicySelector, value: PeerPolicyOverrideValue): Promise<void> {
    await expect(this.peerPolicyToggle(opts)).toHaveAttribute('data-override', value);
  }

  // --- Settings tab: Device Profile form ---------------------------------
  get settingsSaveButton(): Locator {
    return this.tid(TID.settingsSave);
  }
  async setSignerName(value: string): Promise<void> {
    await this.tid(TID.settingsSignerName).fill(value);
  }
  async expectSignerName(value: string): Promise<void> {
    await expect(this.tid(TID.settingsSignerName)).toHaveValue(value);
  }
  async addSettingsRelay(url: string): Promise<void> {
    await this.tid(TID.settingsRelayAddInput).fill(url);
    await this.tid(TID.settingsRelayAddSubmit).click();
  }
  settingsRelayRow(url: string): Locator {
    return this.page.locator(`[data-testid="${TID.settingsRelayRow}"][data-relay-url="${url}"]`);
  }
  async expectSettingsRelay(url: string): Promise<void> {
    await expect(this.settingsRelayRow(url)).toBeVisible();
  }
  settingsNumberField(field: SignerNumberField): Locator {
    return this.page.locator(`[data-testid="${TID.settingsNumberField}"][data-field="${field}"]`);
  }
  async setNumberSetting(field: SignerNumberField, value: number): Promise<void> {
    await this.settingsNumberField(field).fill(String(value));
  }
  async expectNumberSetting(field: SignerNumberField, value: number): Promise<void> {
    await expect(this.settingsNumberField(field)).toHaveValue(String(value));
  }
  async saveSettings(): Promise<void> {
    await this.settingsSaveButton.click();
  }
}

export type PeerPolicyDirection = 'request' | 'respond';
export type PeerPolicyMethod = 'ping' | 'onboard' | 'sign' | 'ecdh';
export type PeerPolicyOverrideValue = 'allow' | 'deny' | 'unset' | 'ask';
export interface PeerPolicySelector {
  pubkey?: string;
  direction: PeerPolicyDirection;
  method: PeerPolicyMethod;
}
export type SignerNumberField =
  | 'sign_timeout_secs'
  | 'ping_timeout_secs'
  | 'request_ttl_secs'
  | 'state_save_interval_secs';

export interface PwaPages {
  welcome: WelcomePage;
  create: CreateFlowPage;
  distribute: DistributePage;
  onboard: OnboardPage;
  import: ImportPage;
  recover: RecoverPage;
  dashboard: DashboardPage;
}

export function pages(page: Page): PwaPages {
  return {
    welcome: new WelcomePage(page),
    create: new CreateFlowPage(page),
    distribute: new DistributePage(page),
    onboard: new OnboardPage(page),
    import: new ImportPage(page),
    recover: new RecoverPage(page),
    dashboard: new DashboardPage(page),
  };
}
