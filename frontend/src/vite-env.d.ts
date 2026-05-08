/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_GUESS_CHAMPION_ADDRESS?: `0x${string}`;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
