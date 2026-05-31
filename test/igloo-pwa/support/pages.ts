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
  async unlock(password: string, profileId?: string): Promise<void> {
    await this.row(profileId).getByTestId(TID.welcomeProfileUnlock).click();
    await this.tid(TID.welcomeUnlockPassword).fill(password);
    await this.tid(TID.welcomeUnlockSubmit).click();
  }
  async openMenu(profileId?: string): Promise<void> {
    await this.row(profileId).getByTestId(TID.welcomeProfileMenuTrigger).click();
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
  async fillGenerate(opts: { groupName?: string; privateKey?: string }): Promise<void> {
    if (opts.groupName != null) await this.page.getByLabel('Group Name').fill(opts.groupName);
    if (opts.privateKey != null) {
      await this.page.getByLabel('Existing Private Key (optional)').fill(opts.privateKey);
    }
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
