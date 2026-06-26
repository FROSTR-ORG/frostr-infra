import { expect, type Locator, type Page } from '@playwright/test';

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
  async selectRotateSource(profileId: string): Promise<void> {
    await this.tid(TID.rotateSourceProfile).selectOption(profileId);
  }
  // Per-source rows are dynamic; located by placeholder/label within the rotate
  // panel (raw locators are allowed inside support, not in specs).
  async fillRotateSource(index: number, opts: { sourcePackage: string; password: string }): Promise<void> {
    await this.page.getByPlaceholder('Paste bfprofile1... or bfshare1...').nth(index).fill(opts.sourcePackage);
    await this.page.getByLabel('Package Password').nth(index).fill(opts.password);
  }
  async expectRotateCollect(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Collect Shares' })).toBeVisible();
    await expect(this.page.getByText('Back to Welcome')).toBeVisible();
    await expect(this.page.getByText('This Device Share (#1)')).toBeVisible();
    await expect(this.tid(TID.rotateLocalPassphrase)).toBeVisible();
    await expect(this.page.getByText('Remote Source #1')).toBeVisible();
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
  async expectGenerateForm(opts: { groupName?: string } = {}): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Create New Keyset' })).toBeVisible();
    if (opts.groupName != null) {
      await expect(this.page.getByLabel('Group Name')).toHaveValue(opts.groupName);
    }
  }
  async expectSelectShareHidden(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Select Share' })).toHaveCount(0);
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

export class DashboardPage extends BasePage {
  async expectDashboard(profileLabel?: string): Promise<void> {
    await expect(this.tid(TID.dashboardRoot)).toBeVisible();
    await expect(this.tid(TID.dashboardTabSigner)).toBeVisible();
    if (profileLabel) {
      await expect(this.tid(TID.dashboardRoot)).toContainText(profileLabel);
    }
  }
  async expectNoDashboard(): Promise<void> {
    await expect(this.tid(TID.dashboardRoot)).toHaveCount(0);
  }
  async expectRoute(tab: 'signer' | 'permissions' | 'settings'): Promise<void> {
    const suffix = tab === 'signer' ? '' : `/${tab}`;
    await expect(this.page).toHaveURL(new RegExp(`/dashboard${suffix}/?$`));
  }
  async openTab(tab: 'signer' | 'permissions' | 'settings'): Promise<void> {
    const id =
      tab === 'signer'
        ? TID.dashboardTabSigner
        : tab === 'permissions'
          ? TID.dashboardTabPermissions
          : TID.dashboardTabSettings;
    await this.tid(id).click();
  }
  async expectDashboardActionActive(
    activeAction: 'dashboard' | 'permissions' | 'settings',
  ): Promise<void> {
    await expect(this.tid(TID.dashboardTabSigner)).toHaveAttribute(
      'aria-pressed',
      String(activeAction === 'dashboard'),
    );
    await expect(this.page.getByRole('button', { name: 'Recover' })).toHaveCount(0);
    await expect(this.tid(TID.dashboardTabPermissions)).toHaveAttribute(
      'aria-pressed',
      String(activeAction === 'permissions'),
    );
    await expect(this.tid(TID.dashboardTabSettings)).toHaveAttribute(
      'aria-pressed',
      String(activeAction === 'settings'),
    );
  }
  async expectNoRuntimeRecoverAction(): Promise<void> {
    await expect(this.page.getByRole('button', { name: 'Recover' })).toHaveCount(0);
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
    await expect(this.tid(TID.settingsProfilePassword)).toBeVisible();
    await expect(this.tid(TID.settingsOnboardDevice)).toBeVisible();
    await expect(this.tid(TID.settingsCopyProfile)).toBeVisible();
    await expect(this.tid(TID.settingsCopyShare)).toBeVisible();
    await expect(this.tid(TID.maintenanceRotateShare)).toBeVisible();
    await expect(this.tid(TID.settingsLogout)).toBeVisible();
    await expect(this.tid(TID.settingsClearCredentials)).toBeVisible();
  }
  async scrollSettingsSidebarToBottom(): Promise<void> {
    await this.tid(TID.dashboardSettingsSidebarBody).evaluate((node) => {
      node.scrollTop = node.scrollHeight;
    });
  }
  async closeSettingsSidebar(): Promise<void> {
    await this.tid(TID.dashboardSettingsSidebarClose).click();
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
  async expectKeyDisplays(groupDisplay: string, hiddenShareDisplay?: string): Promise<void> {
    await expect(this.page.locator('.igloo-dashboard-key-value', { hasText: groupDisplay })).toBeVisible();
    await expect(this.page.getByText('Share Public Key')).toHaveCount(0);
    await expect(this.tid(TID.dashboardShareKeyCopy)).toHaveCount(0);
    if (hiddenShareDisplay) {
      await expect(this.page.locator('.igloo-dashboard-key-value', { hasText: hiddenShareDisplay })).toHaveCount(0);
    }
  }
  async expectKeyCopyControls(): Promise<void> {
    await expect(this.tid(TID.dashboardGroupKeyCopy)).toBeVisible();
    await expect(this.tid(TID.dashboardShareKeyCopy)).toHaveCount(0);
  }
  async expectStoppedSignerDashboard(): Promise<void> {
    const root = this.tid(TID.dashboardRoot);
    await expect(root.getByRole('heading', { name: 'Signer Stopped' })).toBeVisible();
    await expect(root).toContainText('Relays, peers, and signing are offline.');
    await expect(root.getByRole('button', { name: 'Start Signer' })).toBeVisible();
    await expect(root.getByRole('heading', { name: 'Readiness' })).toBeVisible();
    await expect(root).toContainText('Start signer to restore connectivity.');
    await expect(root).toContainText('0 relays connected');
    await expect(root).toContainText('0 peers online');
    await expect(root).toContainText('Signing unavailable');
    await expect(root.getByRole('heading', { name: 'Next Step' })).toBeVisible();
    await expect(root).toContainText('Queued work · preserved');
    await expect(root).toContainText('New signing · blocked');
    await expect(root).toContainText('Policy prompts · paused');
    await expect(root).toContainText('Start when ready.');
    await expect(root.getByRole('heading', { name: 'Peers' })).toHaveCount(0);
    await expect(root.getByRole('heading', { name: 'Pending Approvals' })).toHaveCount(0);
    await expect(root.getByRole('heading', { name: 'Event Log' })).toHaveCount(0);
  }
  async expectAllRelaysOfflineDashboard(): Promise<void> {
    const root = this.tid(TID.dashboardRoot);
    await expect(root.getByRole('heading', { name: 'Signer Running (Degraded)' })).toBeVisible();
    await expect(root).toContainText('All relays unreachable · signing degraded.');
    await expect(root.getByRole('button', { name: 'Stop Signer' })).toBeVisible();
    const readiness = root.getByRole('region', { name: 'Readiness' });
    await expect(readiness).toContainText('All Relays Offline');
    await expect(readiness).toContainText('No relay route to peers.');
    await expect(readiness).toContainText('0 / 2 relays reachable');
    await expect(readiness).toContainText('Ready count degraded');
    const recovery = root.getByRole('region', { name: 'Recovery' });
    await expect(recovery).toContainText('Check network, DNS, and firewall.');
    await expect(recovery).toContainText('Blocked until a relay connects.');
    await expect(recovery.getByRole('button', { name: 'Retry Connections' })).toBeVisible();
    await expect(root.getByRole('heading', { name: 'Peers' })).toHaveCount(0);
    await expect(root.getByRole('heading', { name: 'Pending Approvals' })).toHaveCount(0);
    await expect(root.getByRole('heading', { name: 'Event Log' })).toHaveCount(0);
  }
  async expectSigningBlockedDashboard(): Promise<void> {
    const root = this.tid(TID.dashboardRoot);
    await expect(root.getByRole('heading', { name: 'Signer Running (Degraded)' })).toBeVisible();
    await expect(root).toContainText('Policy or readiness gate active.');
    await expect(root.getByRole('button', { name: 'Stop Signer' })).toBeVisible();
    const commonCauses = root.getByRole('region', { name: 'Common Causes' });
    await expect(commonCauses).toContainText('Signing Blocked');
    await expect(commonCauses).toContainText('Requests held pending clearance.');
    await expect(commonCauses).toContainText('Policy decision pending');
    await expect(commonCauses).toContainText('Not enough ready peers');
    await expect(commonCauses).toContainText('Pool imbalance');
    const operatorAction = root.getByRole('region', { name: 'Operator Action' });
    await expect(operatorAction).toContainText('Clear via permissions or approvals.');
    await expect(operatorAction).toContainText(
      '1 of 2 signing peers are ready. Bring another signing peer online before approving signatures.',
    );
    await expect(root.getByRole('heading', { name: 'Peers' })).toHaveCount(0);
    await expect(root.getByRole('heading', { name: 'Pending Approvals' })).toHaveCount(0);
    await expect(root.getByRole('heading', { name: 'Event Log' })).toHaveCount(0);
  }
  async expectSigningFailedModal(): Promise<void> {
    const dialog = this.page.getByRole('dialog', { name: 'Signing Failed' });
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText(
      'Unable to complete signature for event kind:1. All 3 retry attempts exhausted.',
    );
    await expect(dialog).toContainText(
      'Round: r-0x4f2a · Peers responded: 1/2 · Error: insufficient partial signatures',
    );
    await expect(dialog.getByRole('button', { name: 'Dismiss', exact: true })).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Retry' })).toBeVisible();
  }
  async expectPeerSummary(readyLabel: string, averageLatencyLabel: string): Promise<void> {
    await expect(this.tid(TID.dashboardRoot)).toContainText(readyLabel);
    await expect(this.tid(TID.dashboardRoot)).toContainText(averageLatencyLabel);
  }
  async expectPendingApprovalsEmpty(): Promise<void> {
    await expect(this.tid(TID.dashboardPendingApprovals)).toContainText('No pending approvals');
  }
  async expectPendingApprovals(count: number): Promise<void> {
    const section = this.tid(TID.dashboardPendingApprovals);
    await expect(this.page.getByText(`${count} pending`, { exact: true })).toBeVisible();
    await expect(section).toContainText('Peer #2');
    await expect(section).toContainText('kind:1 Short Text Note');
    await expect(section).toContainText('NIP-44 key exchange');
  }
  async expectEventLogSummary(eventCountLabel: string, filterCountLabel: string): Promise<void> {
    const root = this.tid(TID.dashboardRoot);
    await expect(root.getByText(eventCountLabel, { exact: true })).toBeVisible();
    await expect(root.getByRole('button', { name: new RegExp(`Filter\\s+${filterCountLabel}`) })).toBeVisible();
    await expect(root.getByRole('button', { name: 'Clear' })).toBeVisible();
    await expect(root.getByRole('button', { name: 'All' })).toHaveCount(0);
  }
  // Permissions page (peer-only on the PWA; the site/origin section is chrome-only).
  async expectPeerPermissions(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Peer Permissions' })).toBeVisible();
  }
  async expectNoSignerPermissions(): Promise<void> {
    // The PWA signer has no website/origin permissions, so that section must not render.
    await expect(this.page.getByRole('heading', { name: 'Signer Permissions' })).toHaveCount(0);
  }
  async toggleFirstPeerPermission(
    direction: 'request' | 'respond',
    method: 'sign' | 'ecdh' | 'ping' | 'onboard',
    state: 'allow' | 'deny',
  ): Promise<void> {
    const panel = this.page.getByRole('tabpanel', { name: 'Permissions' });
    const token = panel.getByRole('button', { name: `${direction} ${method}: ${state}`, exact: true }).first();
    await token.scrollIntoViewIfNeeded();
    await token.click({ force: true });
  }
  async expectPeerPermission(
    direction: 'request' | 'respond',
    method: 'sign' | 'ecdh' | 'ping' | 'onboard',
    state: 'allow' | 'deny',
  ): Promise<void> {
    const panel = this.page.getByRole('tabpanel', { name: 'Permissions' });
    await expect(panel.getByRole('button', { name: `${direction} ${method}: ${state}`, exact: true }).first()).toBeVisible();
  }
  // Settings sidebar (Paper-aligned section layout).
  async expectSettingsSections(): Promise<void> {
    const sidebar = this.tid(TID.dashboardSettingsSidebar);
    await expect(sidebar).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Device Profile', exact: true })).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Group Profile', exact: true })).toBeVisible();
    await expect(sidebar.getByText('2 of 3', { exact: true })).toBeVisible();
    await expect(sidebar.getByText('Updated', { exact: true })).toBeVisible();
    await expect(sidebar.getByText('threshold n/a', { exact: true })).toHaveCount(0);
    await expect(this.page.getByRole('heading', { name: 'Onboard Device', exact: true })).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Replace Share', exact: true }).first()).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Export Profile', exact: true })).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Export Share', exact: true })).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Browser Settings', exact: true })).toBeVisible();
    await expect(sidebar.getByText('Remember browser state', { exact: true })).toBeVisible();
    await expect(sidebar.getByText('Open signer after import', { exact: true })).toBeVisible();
    await expect(sidebar.getByText('Prefer install prompt', { exact: true })).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Logout', exact: true })).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Clear Credentials', exact: true })).toBeVisible();
  }
  async expectSettingsSidebarFitsViewport(): Promise<void> {
    const sidebar = this.tid(TID.dashboardSettingsSidebar);
    const body = this.tid(TID.dashboardSettingsSidebarBody);
    const viewportWidth = await this.page.evaluate(() => window.innerWidth);
    await expect(sidebar).toBeVisible();
    await expect.poll(async () => sidebar.evaluate(readCssBackgroundAlpha)).toBe(1);
    await expect
      .poll(async () => this.page.evaluate(() => document.documentElement.scrollWidth))
      .toBe(viewportWidth);
    await expect
      .poll(async () =>
        sidebar.evaluate((node) => {
          const rect = node.getBoundingClientRect();
          return {
            left: Math.round(rect.left),
            right: Math.round(rect.right),
            viewportWidth: window.innerWidth,
          };
        }),
      )
      .toEqual(
        expect.objectContaining({
          left: 0,
          right: viewportWidth,
        }),
      );
    await expect
      .poll(async () => body.evaluate((node) => node.scrollWidth - node.clientWidth))
      .toBe(0);
  }
  async expectSettingsSidebarClosed(): Promise<void> {
    await expect(this.tid(TID.dashboardSettingsSidebar)).toHaveCount(0);
  }
  // Export package modal (Phase B step 4).
  async openExportProfile(): Promise<void> {
    await this.tid(TID.settingsCopyProfile).click();
  }
  async openExportShare(): Promise<void> {
    await this.tid(TID.settingsCopyShare).click();
  }
  async openOnboardDevice(): Promise<void> {
    await this.tid(TID.settingsOnboardDevice).click();
  }
  async expectOnboardDeviceConfigureForm(): Promise<void> {
    const dialog = this.page.getByRole('dialog', { name: 'Onboard a Device' });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('heading', { name: 'Configure Device' })).toBeVisible();
    await expect(dialog.getByText(/remote-member bfshare/i)).toBeVisible();
    await expect(this.tid(TID.settingsOnboardDeviceLabel)).toBeVisible();
    await expect(this.tid(TID.settingsOnboardSourcePackage)).toBeVisible();
    await expect(this.tid(TID.settingsOnboardSourcePassword)).toBeVisible();
    await expect(this.tid(TID.settingsOnboardPackagePassword)).toBeVisible();
    await expect(this.tid(TID.settingsOnboardPackageConfirm)).toBeVisible();
    await expect(this.tid(TID.settingsOnboardCreate)).toBeDisabled();
  }
  async closeOnboardDeviceConfigureForm(): Promise<void> {
    await this.page.getByRole('dialog', { name: 'Onboard a Device' }).getByRole('button', { name: 'Cancel' }).click();
  }
  async expectOnboardDeviceHandoff(): Promise<void> {
    const dialog = this.page.getByRole('dialog', { name: 'Onboard a Device' });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('heading', { name: 'Package Handoff' })).toBeVisible();
    await expect(this.tid(TID.settingsOnboardResult)).toBeVisible();
    await expect(dialog.getByText('Remote Device is ready as an encrypted bfonboard package.')).toBeVisible();
    await expect(dialog.getByText('Share #2')).toBeVisible();
    await expect(dialog.locator('textarea')).toHaveValue(/bfonboard1/);
    await expect(this.tid(TID.settingsOnboardCopy)).toBeVisible();
    await expect(this.tid(TID.settingsOnboardSave)).toBeVisible();
    await expect(this.tid(TID.settingsOnboardQr)).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Done' })).toBeVisible();
  }
  async openProfilePassword(): Promise<void> {
    await this.tid(TID.settingsProfilePassword).click();
  }
  async expectProfilePasswordModal(): Promise<void> {
    const dialog = this.page.getByRole('dialog', { name: 'Change Profile Password' });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(/Re-encrypt this device profile/i)).toBeVisible();
    await expect(this.tid(TID.settingsPasswordCurrent)).toBeVisible();
    await expect(this.tid(TID.settingsPasswordNext)).toBeVisible();
    await expect(this.tid(TID.settingsPasswordConfirm)).toBeVisible();
  }
  async cancelProfilePassword(): Promise<void> {
    await this.page
      .getByRole('dialog', { name: 'Change Profile Password' })
      .getByRole('button', { name: 'Cancel' })
      .click();
  }
  async openClearCredentials(): Promise<void> {
    await this.tid(TID.settingsClearCredentials).click();
  }
  async expectClearCredentialsModal(): Promise<void> {
    const dialog = this.page.getByRole('dialog', { name: 'Clear Credentials' });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(/This action cannot be undone/i)).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Clear Credentials' })).toBeVisible();
  }
  async cancelClearCredentials(): Promise<void> {
    await this.page.getByRole('dialog', { name: 'Clear Credentials' }).getByRole('button', { name: 'Cancel' }).click();
  }
  async openReplaceShare(): Promise<void> {
    await this.tid(TID.maintenanceRotateShare).click();
  }
  async expectReplaceShareApplying(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Applying Replacement' })).toBeVisible();
    await expect(this.page.getByText('Validated package')).toBeVisible();
    await expect(this.page.getByText('Matched Group Profile')).toBeVisible();
    await expect(this.page.getByText('Replacing local share')).toBeVisible();
    await expect(this.page.getByText('Saving updated local share')).toBeVisible();
  }
  async expectReplaceShareFailed(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Replacement Failed' })).toBeVisible();
    await expect(this.page.getByText('Replacement package did not apply')).toBeVisible();
    await expect(this.page.getByRole('button', { name: 'Retry' })).toBeVisible();
    await expect(this.page.getByText('Back to Replace Share', { exact: true })).toBeVisible();
  }
  async expectReplaceShareSuccess(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Share Replaced' })).toBeVisible();
    await expect(this.page.getByText('Replacement share is active on this device')).toBeVisible();
    await expect(this.page.getByText('Replacement Summary')).toBeVisible();
    await expect(this.page.getByText('Return to Signer', { exact: true })).toBeVisible();
  }
  async expectExportModalEntry(): Promise<void> {
    await expect(this.tid(TID.exportPassword)).toBeVisible();
    await expect(this.tid(TID.exportConfirm)).toBeVisible();
    await expect(this.tid(TID.exportSubmit)).toBeVisible();
  }
  get exportPasswordInput(): Locator {
    return this.tid(TID.exportPassword);
  }
  get exportPasswordFieldShell(): Locator {
    return this.page.getByRole('dialog').locator('.igloo-export-field .igloo-password-field').first();
  }
  async expectNoShareKeyCopy(): Promise<void> {
    await expect(this.tid(TID.dashboardShareKeyCopy)).toHaveCount(0);
  }
  get settingsProfileNameInput(): Locator {
    return this.page.getByLabel('Profile Name');
  }
  get settingsRelayInput(): Locator {
    return this.tid(TID.relayAddInput);
  }
  // Makes the Settings form dirty by editing the signer name (Device Profile).
  async editSignerName(value: string): Promise<void> {
    await this.page.getByPlaceholder('Unnamed signer').fill(value);
  }
  async addSettingsRelay(url: string): Promise<void> {
    await this.page.getByLabel('New relay URL').fill(url);
    await this.page.getByRole('button', { name: 'Add' }).click();
  }
  async saveSettings(): Promise<void> {
    await this.page.getByRole('button', { name: 'Save Changes' }).click();
    await this.expectSettingsSidebarClosed();
  }
  async expectSignerName(value: string): Promise<void> {
    await expect(this.page.getByLabel('Profile Name')).toHaveValue(value);
  }
  async expectSettingsRelay(url: string): Promise<void> {
    await expect(this.tid(TID.dashboardSettingsSidebar).getByText(url, { exact: true })).toBeVisible();
  }
  // Unsaved-changes guard modal (leaving Settings with edits).
  async expectUnsavedGuard(): Promise<void> {
    const dialog = this.page.getByRole('dialog', { name: 'Discard unsaved changes?' });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText('You have unsaved changes in Settings. Close without saving?')).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Keep editing' })).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Discard' })).toBeVisible();
  }
  async keepEditing(): Promise<void> {
    await this.page.getByRole('button', { name: 'Keep editing' }).click();
  }
  async discardChanges(): Promise<void> {
    await this.page.getByRole('button', { name: 'Discard' }).click();
  }
  // Drives the export modal to completion and returns the re-encrypted package text.
  async exportProfileWithPassword(password: string): Promise<string> {
    await this.openExportProfile();
    await this.expectExportModalEntry();
    await this.tid(TID.exportPassword).fill(password);
    await this.tid(TID.exportConfirm).fill(password);
    await this.tid(TID.exportSubmit).click();
    const result = this.tid(TID.exportResult);
    await expect(result).toBeVisible({ timeout: 30_000 });
    return (await result.textContent()) ?? '';
  }
}

function readCssBackgroundAlpha(node: Element): number {
  const backgroundColor = window.getComputedStyle(node).backgroundColor;
  const rgbMatch = backgroundColor.match(/^rgba?\((.+)\)$/);
  if (rgbMatch) {
    const channels = rgbMatch[1].split(',').map((part) => part.trim());
    return channels.length >= 4 ? Number.parseFloat(channels[3]) : 1;
  }
  const colorFunctionAlphaMatch = backgroundColor.match(/\/\s*([0-9.]+%?)/);
  if (colorFunctionAlphaMatch) {
    const rawAlpha = colorFunctionAlphaMatch[1];
    return rawAlpha.endsWith('%') ? Number.parseFloat(rawAlpha) / 100 : Number.parseFloat(rawAlpha);
  }
  return backgroundColor === 'transparent' ? 0 : 1;
}

export interface PwaPages {
  welcome: WelcomePage;
  create: CreateFlowPage;
  distribute: DistributePage;
  onboard: OnboardPage;
  import: ImportPage;
  dashboard: DashboardPage;
}

export function pages(page: Page): PwaPages {
  return {
    welcome: new WelcomePage(page),
    create: new CreateFlowPage(page),
    distribute: new DistributePage(page),
    onboard: new OnboardPage(page),
    import: new ImportPage(page),
    dashboard: new DashboardPage(page),
  };
}
