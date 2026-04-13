# Audio Visualizer (PDM) – Nexys A7-50T

## Členové týmu

| Jméno | Role |
|---|---|
| Jan Maláč | PDM driver, top-level |
| Peter Rafaelis | PDM filtr, sensitivity_ctrl, testbench |
| Marek Raus | LED bar, peak_hold, dokumentace |

---

## Obsah

- [Cíl projektu](#cíl-projektu)
- [Lab 1: Architecture](#lab-1-architecture)
- [Lab 2: Unit Design](#lab-2-unit-design)
- [Lab 3: Integration](#lab-3-integration)
- [Lab 4: Tuning](#lab-4-tuning)
- [Lab 5: Defense](#lab-5-defense)

---

## Cíl projektu

Cílem projektu je zobrazení intenzity zvukového signálu v reálném čase pomocí 16 LED na desce Nexys A7-50T. Deska obsahuje zabudovaný MEMS mikrofon s PDM (Pulse Density Modulation) rozhraním. FPGA čte 1-bitový PDM datový tok, zpracuje ho decimačním filtrem a výslednou amplitudu zobrazí jako sloupcový VU metr na LED. Uživatel může pomocí tlačítek měnit citlivost a režim zobrazení.

### Základní funkce

- Čtení PDM dat z onboard MEMS mikrofonu
- Decimační filtr (akumulátor) pro převod PDM → amplituda
- Zobrazení hlasitosti na 16x LED jako VU metr
- Nastavitelná citlivost mikrofonu tlačítky BTNL / BTNR
- Režim Peak Hold – LED drží poslední maximum, přepíná BTNU
- Reset peak hodnoty tlačítkem BTND
- Reset celého systému tlačítkem BTNC

### Ovládání tlačítky

| Tlačítko | Pin | Funkce |
|---|---|---|
| **BTNC** | N17 | Reset – výchozí stav (citlivost střední, peak hold vypnutý) |
| **BTNL** | P17 | Snížení citlivosti – reaguje méně na slabé zvuky |
| **BTNR** | M17 | Zvýšení citlivosti – reaguje více na slabé zvuky |
| **BTNU** | M18 | Zapnutí / vypnutí režimu Peak Hold |
| **BTND** | P18 | Ruční reset peak hold hodnoty |

---

## Lab 1: Architecture

### Blokové schéma

*Viz soubor `img/block_diagram.png`*

```
                     ┌──────────────────────────────────────────────────┐
                     │                    TOP LEVEL                     │
                     │                                                  │
 CLK (100 MHz) ─────►│  clk_en ──► pdm_driver ──────────► MIC_CLK    │──► MIC_CLK
                     │                  │                               │
                     │            MIC_DATA ◄──────────────────────────│◄── MIC_DATA
                     │                  │                               │
                     │   BTNL/BTNR ──► debounce ──► sensitivity_ctrl   │
                     │                                      │ window    │
                     │                             pdm_filter           │
                     │                                      │ pcm_data  │
                     │   BTNU/BTND ──► debounce ──► peak_hold          │
                     │                                      │ level     │
                     │                               led_bar ──────────│──► LED[15:0]
                     │                                                  │
 RST (BTNC) ────────►│                                                  │
                     └──────────────────────────────────────────────────┘
```

### Popis modulů

| Modul | Soubor | Popis |
|---|---|---|
| `clk_en` | `src/clk_en.vhd` | Standardní lab komponenta – hodinový enable |
| `debounce` | `src/debounce.vhd` | Ošetření zákmitů pro všechna tlačítka |
| `pdm_driver` | `src/pdm_driver.vhd` | Generuje clock pro mikrofon (~3.125 MHz), čte PDM data |
| `sensitivity_ctrl` | `src/sensitivity_ctrl.vhd` | Mění velikost okna filtru dle tlačítek BTNL/BTNR |
| `pdm_filter` | `src/pdm_filter.vhd` | Akumulátor – počítá '1' za nastavitelné okno vzorků |
| `peak_hold` | `src/peak_hold.vhd` | Drží maximální hodnotu, přepíná BTNU, resetuje BTND |
| `led_bar` | `src/led_bar.vhd` | Převede amplitudu 0–255 na 0–16 LED, bliká při peak hold |
| `top_level` | `src/top_level.vhd` | Propojení všech modulů |

### Příprava .XDC souboru

| Signál | Pin | Popis |
|---|---|---|
| `clk` | E3 | 100 MHz hlavní hodiny |
| `rst` | N17 | Reset (BTNC) |
| `btn_l_i` | P17 | Snížení citlivosti (BTNL) |
| `btn_r_i` | M17 | Zvýšení citlivosti (BTNR) |
| `btn_u_i` | M18 | Peak Hold on/off (BTNU) |
| `btn_d_i` | P18 | Reset peak hold (BTND) |
| `mic_clk_o` | J5 | Clock do MEMS mikrofonu |
| `mic_data_i` | H5 | PDM data z mikrofonu |
| `mic_lr_sel_o` | F5 | Výběr kanálu (L/R) |
| `led_o[0..15]` | H17..V11 | 16x LED |

---

## Lab 2: Unit Design

### debounce

Ošetřuje zákmity mechanických tlačítek. Vzorkuje vstup každé 2 ms pomocí posuvného registru a propustí stabilní hodnotu jako jednorázový pulz.

#### Porty

| Port | Směr | Typ | Popis |
|---|---|---|---|
| `clk` | in | std_logic | Hlavní hodiny 100 MHz |
| `rst` | in | std_logic | Synchronní reset, active high |
| `btn_i` | in | std_logic | Surový vstup tlačítka |
| `btn_o` | out | std_logic | Ošetřený výstup – 1 pulz na 1 stisk |

#### VHDL kód

```vhdl
entity debounce is
    generic (
        G_MAX : positive := 200_000  -- 2 ms @ 100 MHz; pro simulaci použij 2
    );
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        btn_i : in  std_logic;
        btn_o : out std_logic
    );
end entity debounce;
```

---

### pdm_driver

Generuje clock pro mikrofon (100 MHz / 32 = 3.125 MHz) a čte PDM bity na každou náběžnou hranu mic_clk.

#### Porty

| Port | Směr | Typ | Popis |
|---|---|---|---|
| `clk` | in | std_logic | Hlavní hodiny 100 MHz |
| `rst` | in | std_logic | Synchronní reset |
| `mic_clk_o` | out | std_logic | Clock do mikrofonu |
| `mic_lr_sel_o` | out | std_logic | Výběr kanálu – fixně '0' (levý) |
| `mic_data_i` | in | std_logic | PDM data z mikrofonu |
| `pdm_data_o` | out | std_logic | Vzorkovaný PDM bit |
| `pdm_valid_o` | out | std_logic | '1' = nový platný PDM bit |

#### VHDL kód

```vhdl
entity pdm_driver is
    generic (
        G_CLK_DIV : positive := 32  -- 100MHz / 32 = 3.125 MHz
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        mic_clk_o    : out std_logic;
        mic_lr_sel_o : out std_logic;
        mic_data_i   : in  std_logic;
        pdm_data_o   : out std_logic;
        pdm_valid_o  : out std_logic
    );
end entity pdm_driver;
```

---

### sensitivity_ctrl

Nastavuje velikost okna filtru. BTNR zvyšuje citlivost (menší okno), BTNL ji snižuje (větší okno). 5 kroků po 32, rozsah 32–224.

#### Porty

| Port | Směr | Typ | Popis |
|---|---|---|---|
| `clk` | in | std_logic | Hlavní hodiny |
| `rst` | in | std_logic | Synchronní reset |
| `btn_up_i` | in | std_logic | BTNR – zvýšení citlivosti |
| `btn_dn_i` | in | std_logic | BTNL – snížení citlivosti |
| `window_o` | out | std_logic_vector(7 downto 0) | Velikost okna (32–224) |

#### VHDL kód

```vhdl
entity sensitivity_ctrl is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        btn_up_i : in  std_logic;
        btn_dn_i : in  std_logic;
        window_o : out std_logic_vector(7 downto 0)
    );
end entity sensitivity_ctrl;
```

---

### pdm_filter

Akumulátor počítá jedničky za okno N PDM bitů. Velikost okna určuje `sensitivity_ctrl`. Výsledek odpovídá amplitudě signálu.

#### Porty

| Port | Směr | Typ | Popis |
|---|---|---|---|
| `clk` | in | std_logic | Hlavní hodiny |
| `rst` | in | std_logic | Synchronní reset |
| `window_i` | in | std_logic_vector(7 downto 0) | Velikost okna ze sensitivity_ctrl |
| `pdm_data_i` | in | std_logic | PDM bit z driveru |
| `pdm_valid_i` | in | std_logic | Platný PDM bit |
| `pcm_data_o` | out | std_logic_vector(7 downto 0) | Amplituda 0–255 |
| `pcm_valid_o` | out | std_logic | Nová platná hodnota |

#### VHDL kód

```vhdl
entity pdm_filter is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        window_i    : in  std_logic_vector(7 downto 0);
        pdm_data_i  : in  std_logic;
        pdm_valid_i : in  std_logic;
        pcm_data_o  : out std_logic_vector(7 downto 0);
        pcm_valid_o : out std_logic
    );
end entity pdm_filter;
```

#### Simulace (tb_pdm_filter)

![Simulace pdm_filter](img/simulation_pdm_filter.png)
*Obr. 1: Behaviorální simulace modulu pdm_filter. Signál pcm_data postupně nabývá hodnot:
0x00 (ticho), 0x20 (střední hlasitost), 0x3E (hlasitý zvuk) a 0x11 po změně okna na 32 vzorků.*

---

### peak_hold

Drží maximální hodnotu amplitudy. BTNU přepíná Peak Hold on/off, BTND resetuje maximum na aktuální hodnotu.

#### Porty

| Port | Směr | Typ | Popis |
|---|---|---|---|
| `clk` | in | std_logic | Hlavní hodiny |
| `rst` | in | std_logic | Synchronní reset |
| `btn_mode_i` | in | std_logic | BTNU – přepnutí Peak Hold |
| `btn_reset_i` | in | std_logic | BTND – reset peak hodnoty |
| `level_i` | in | std_logic_vector(7 downto 0) | Aktuální amplituda |
| `valid_i` | in | std_logic | Nová platná hodnota |
| `level_o` | out | std_logic_vector(7 downto 0) | Výstup (peak nebo přímá hodnota) |
| `peak_active_o` | out | std_logic | '1' = Peak Hold je zapnutý |

#### VHDL kód

```vhdl
entity peak_hold is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        btn_mode_i    : in  std_logic;
        btn_reset_i   : in  std_logic;
        level_i       : in  std_logic_vector(7 downto 0);
        valid_i       : in  std_logic;
        level_o       : out std_logic_vector(7 downto 0);
        peak_active_o : out std_logic
    );
end entity peak_hold;
```

---

### led_bar

Převede amplitudu (0–255) na počet rozsvícených LED (0–16). Při aktivním Peak Hold bliká nejvyšší rozsvícená LED (~6 Hz).

#### Porty

| Port | Směr | Typ | Popis |
|---|---|---|---|
| `clk` | in | std_logic | Hlavní hodiny |
| `rst` | in | std_logic | Synchronní reset |
| `level_i` | in | std_logic_vector(7 downto 0) | Amplituda 0–255 |
| `valid_i` | in | std_logic | Nová platná hodnota |
| `peak_active_i` | in | std_logic | Peak Hold aktivní |
| `led_o` | out | std_logic_vector(15 downto 0) | 16 LED výstupů |

#### VHDL kód

```vhdl
entity led_bar is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        level_i       : in  std_logic_vector(7 downto 0);
        valid_i       : in  std_logic;
        peak_active_i : in  std_logic;
        led_o         : out std_logic_vector(15 downto 0)
    );
end entity led_bar;
```
<img width="1482" height="830" alt="image" src="https://github.com/user-attachments/assets/0e6ff2f1-5520-4856-bd2f-f80278f6f72d" />
*Obr. 1: Behaviorální simulace modulu pdm_filter. Signál pcm_data postupně nabývá hodnot:
0x00 (ticho), 0x20 (střední hlasitost), 0x3E (hlasitý zvuk) a 0x11 po změně okna na 32 vzorků.*
---

## Lab 3: Integration

*Bude doplněno – top_level.vhd, syntéza, testování na HW.*

---

## Lab 4: Tuning

*Bude doplněno – ladění, optimalizace.*

---

## Lab 5: Defense

*Bude doplněno – video, poster, resource report.*

### Resource Report (po syntéze)

| Resource | Used | Available | Utilization |
|---|---|---|---|
| LUT | – | 20800 | – |
| FF | – | 41600 | – |
| BRAM | – | 50 | – |
| IO | – | 210 | – |

---

## Reference

- [Nexys A7 Reference Manual](https://digilent.com/reference/programmable-logic/nexys-a7/reference-manual)
- [PDM Microphone Datasheet – SPH0641LU4H-1](https://www.knowles.com/docs/default-source/default-document-library/sph0641lu4h-1-datasheet.pdf)
- [tomas-fryza/vhdl-examples](https://github.com/tomas-fryza/vhdl-examples)
- Vivado 2025.2
- [draw.io](https://draw.io) – blokové schéma
