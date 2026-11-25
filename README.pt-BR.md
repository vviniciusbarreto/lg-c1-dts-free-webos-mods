# DTS Free LG TV C1 - WebOS Rooted + Visual Mods

Selos de áudio (DTS / Dolby) no estilo nativo da LG, correção do eARC depois do boot e DTS mais cedo no boot, para TVs LG webOS com root.

[English](README.md)

Complemento para o [dts_restore_plus](https://github.com/josippapez/dts_restore_plus), de josippapez,
que devolve o DTS (com passthrough pelo ARC/eARC) às TVs LG que perderam o suporte. Este repositório
**não** inclui nem modifica o código dele: ele é um pré-requisito.

Testado numa LG OLED C1 (webOS 6, GStreamer 1.16) com soundbar no eARC.

## O que faz

- **Selos de áudio no estilo nativo da LG.** Mostra, no mesmo aviso do canto superior direito que a TV usa
  para "HDR" e "Dolby Vision", com a mesma animação e duração (é o próprio aviso do sistema, tipo `light`):
  - "DTS Digital Surround" quando o DTS vai direto para o receiver (ou "DTS Digital Surround (TV)" se a TV decodificar);
  - "Dolby Digital" (AC3), "Dolby Digital Plus" (E-AC3) e "Dolby Atmos" (E-AC3 com Atmos).
  O selo entra depois do selo HDR/Dolby Vision da LG, nunca por cima.
  Vale também para as entradas HDMI (ex.: um console mandando Dolby Atmos em passthrough, que a LG não avisa).
- **Correção do eARC depois do boot.** Em algumas TVs, depois de um boot completo, o eARC conecta sem concluir
  a sincronia com a soundbar e o DTS em passthrough vira chiado. Desligar e religar "Compatibilidade com eARC"
  resolve; o script faz isso sozinho ~1 min depois do boot (o som some por ~3 s uma vez) e confere no log.
- **DTS mais cedo no boot.** Roda o script do dts_restore_plus no começo da fila de inicialização do webosbrew
  (~10 s antes), para diminuir a chance de um app abrir um filme antes do DTS estar ativo.

## Requisitos

- TV LG com root e [Homebrew Channel / webosbrew](https://www.webosbrew.org/) (pasta `/var/lib/webosbrew/init.d`).
- [dts_restore_plus](https://github.com/josippapez/dts_restore_plus) instalado (para o passthrough: `install.sh --passthrough`).
- Acesso SSH como root (não telnet).

## Instalar

Copie esta pasta para a TV (ex.: `scp -r`), entre nela por SSH e rode:

```sh
sh install.sh
```

Para remover: `sh uninstall.sh` (não mexe no dts_restore_plus). Se for desinstalar o dts_restore_plus,
rode também o `uninstall.sh` daqui, para apagar o `00-dts-early`.

## Ícone DTS

Nenhuma arte de marca vem neste repositório. O selo Dolby usa o ícone que já existe na própria TV
(`/usr/share/pqcontroller/images/light_toast_icon_dolby.png`). Para o ícone DTS, gere um a partir de um SVG
oficial do logo "dts" que você tenha (retire o ® do SVG antes, porque nesse tamanho ele vira um ponto):

```sh
pip install cairosvg pillow
python3 tools/make_dts_icon.py dts_logo.svg dts_icon.png
```

Coloque o `dts_icon.png` ao lado do `install.sh` antes de instalar. Sem ele, o selo DTS sai só com o texto.

## Desligar partes

| O quê | Como |
|---|---|
| Todos os selos | `touch /var/lib/webosbrew/dts_badge/disabled` |
| Só os selos Dolby | `touch /var/lib/webosbrew/dts_badge/disabled_dolby` |
| Só os selos das entradas HDMI | `touch /var/lib/webosbrew/dts_badge/disabled_hdmi` |
| Correção do eARC | `touch /var/lib/webosbrew/dts_badge/disabled_earc_fix` |

Logs: `/tmp/dts_badge.log`, `/tmp/earc_fix.log`.

## Como funciona

- O selo nativo da LG é um `luna://com.webos.notification/createToast` com `"type":"light"` (é o que o
  `pqcontroller` usa para HDR/Dolby Vision). O script usa o mesmo aviso, com outro ícone e texto.
- DTS: lê a decisão que o dtsdec do dts_restore_plus grava em `/run/dtsc1/last-decision`.
- Dolby: lê as linhas `setDecodeInfo` de áudio do `/tmp/var/log/dbg-log` (`codec` e `immersive`).
- eARC: alterna `eArcSupport` por `com.webos.settingsservice/setSystemSettings` e confere
  `audioDeviceType[sound_mode_sync]` nas mensagens do `arccontroller`.
- Todos os scripts de inicialização saem sempre com 0, para não acionar o modo de segurança do webosbrew.

## Avisos

- Uma atualização de firmware da LG pode remover o root; mantenha o bloqueio de atualizações do Homebrew Channel ligado.
- Se você ligar a TV e abrir um filme com DTS nos primeiros segundos, o app pode receber "codec não suportado"
  antes de o dts_restore_plus estar ativo. Basta abrir o filme de novo.
- Projeto não oficial, sem relação com LG, Dolby ou DTS. Use por sua conta.

## Créditos

- [dts_restore_plus](https://github.com/josippapez/dts_restore_plus), de josippapez, baseado no trabalho
  de Pete Batard ([RootMyTV #72](https://github.com/RootMyTV/RootMyTV.github.io/issues/72)). Licenças próprias (LGPL-2.1 / GPL-2.0).
- [webosbrew](https://www.webosbrew.org/) / Homebrew Channel.
