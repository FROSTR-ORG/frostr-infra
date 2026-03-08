declare const chrome: any;

type TestNostrApi = {
  getPublicKey?: () => Promise<string>;
  getRelays?: () => Promise<unknown>;
  signEvent?: (event: unknown) => Promise<unknown>;
  nip44?: {
    encrypt: (pubkey: string, value: string) => Promise<string>;
    decrypt: (pubkey: string, value: string) => Promise<string>;
  };
};

interface Window {
  nostr?: TestNostrApi;
}
