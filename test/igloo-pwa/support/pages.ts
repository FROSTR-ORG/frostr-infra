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
  async selectMode(mode: 'new' | 'rotate'): Promise<void> {
    await this.tid(mode === 'new' ? TID.createModeNew : TID.createModeRotate).click();
  }
  async selectRotateSource(profileId: string): Promise<void> {
    await this.tid(TID.rotateSourceProfile).selectOption(profileId);
  }
  // Per-source rows are dynamic; located by placeholder/label within the rotate
  // panel (raw locators are allowed inside support, not in specs).
  async fillRotateSource(index: number, opts: { bfshare: string; password: string }): Promise<void> {
    await this.page.getByPlaceholder('Paste bfshare1...').nth(index).fill(opts.bfshare);
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

export class DashboardPage extends BasePage {
  async expectDashboard(profileLabel?: string): Promise<void> {
    await expect(this.tid(TID.dashboardRoot)).toBeVisible();
    await expect(this.tid(TID.dashboardTabSigner)).toBeVisible();
    if (profileLabel) {
      await expect(this.tid(TID.dashboardRoot)).toContainText(profileLabel);
    }
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
  // Permissions page (peer-only on the PWA; the site/origin section is chrome-only).
  async expectPeerPermissions(): Promise<void> {
    await expect(this.page.getByRole('heading', { name: 'Peer Permissions' })).toBeVisible();
  }
  async expectNoSignerPermissions(): Promise<void> {
    // The PWA signer has no website/origin permissions, so that section must not render.
    await expect(this.page.getByRole('heading', { name: 'Signer Permissions' })).toHaveCount(0);
  }
  // Settings sidebar (Paper-aligned section layout).
  async expectSettingsSections(): Promise<void> {
    const sidebar = this.tid(TID.dashboardSettingsSidebar);
    await expect(sidebar).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Device Profile', exact: true })).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Group Profile', exact: true })).toBeVisible();
    await expect(sidebar.getByText('2 of 3', { exact: true })).toBeVisible();
    await expect(sidebar.getByText('Updated', { exact: true })).toBeVisible();
    await expect(sidebar.getByText('Nov 15, 2023', { exact: true })).toBeVisible();
    await expect(sidebar.getByText('threshold n/a', { exact: true })).toHaveCount(0);
    await expect(this.page.getByRole('heading', { name: 'Onboard Device', exact: true })).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Replace Share', exact: true }).first()).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Export Profile', exact: true })).toBeVisible();
    await expect(this.page.getByRole('heading', { name: 'Export Share', exact: true })).toBeVisible();
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
  // Export package modal (Phase B step 4).
  async openExportProfile(): Promise<void> {
    await this.tid(TID.settingsCopyProfile).click();
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
    await expect(this.page.getByText('Onboarding package did not apply')).toBeVisible();
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
  // Makes the Settings form dirty by editing the signer name (Device Profile).
  async editSignerName(value: string): Promise<void> {
    await this.page.getByPlaceholder('Unnamed signer').fill(value);
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
