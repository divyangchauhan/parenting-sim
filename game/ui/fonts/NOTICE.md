# Fonts — licenses

Both fonts are licensed under the SIL Open Font License, Version 1.1 (OFL).
Full license texts are committed alongside the fonts.

- **Lora.ttf** — *Lora* (humanist serif), used for prompts, dialogue, titles,
  interstitial / ending body voice. Copyright 2011 The Lora Project Authors.
  License: `LORA-OFL.txt`. Source: https://github.com/google/fonts/tree/main/ofl/lora

- **Inter.ttf** — *Inter* (humanist sans), used for HUD, labels, buttons,
  settings controls. Copyright 2020 The Inter Project Authors.
  License: `INTER-OFL.txt`. Source: https://github.com/google/fonts/tree/main/ofl/inter

Both are variable fonts (weight axis). In `theme.tres` we reference them via
`FontVariation` resources that pin the weight per role (regular for body,
semibold/medium for titles and emphasis).
