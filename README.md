# Audio Visualizer (PDM) – Nexys A7-50T

## Členové týmu

| Jméno | Role |
|---|---|
| Jan Maláč | PDM driver, top-level |
| Peter Rafaelis | PDM filtr, testbench |
| Marek Raus | LED bar driver, dokumentace |

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

Cílem projektu je zobrazení intenzity zvukového signálu v reálném čase pomocí 16 LED na desce Nexys A7-50T. Deska obsahuje zabudovaný MEMS mikrofon s PDM (Pulse Density Modulation) rozhraním. FPGA čte 1-bitový PDM datový tok, zpracuje ho pomocí akumulátorového filtru a výslednou amplitudu zobrazí jako sloupcový VU metr na LED.

### Základní funkce

- Čtení PDM dat z onboard MEMS mikrofonu
- Decimační filtr (akumulátor) pro převod PDM → amplituda
- Zobrazení hlasitosti na 16x LED (čím víc LED svítí, tím víc hluku)
- Reset tlačítkem BTNC

---

## Lab 1: Architecture

### Blokové schéma

```
                        ┌──────────────────────────────────────┐
                        │            TOP LEVEL                 │
                        │                                      │
  CLK (100 MHz) ───────►│  clk_en ──► pdm_driver ──► MIC_CLK │──► MIC_CLK
                        │                 │                    │
                        │           MIC_DATA ◄────────────────│◄── MIC_DATA
                        │                 │                    │
                        │           pdm_filter                 │
                        │                 │                    │
                        │        amplitude_meter               │
                        │                 │                    │
  RST (BTNC) ──────────►│           led_bar ──────────────────│──► LED[15:0]
                        └──────────────────────────────────────┘
```

### Popis modulů

| Modul | Soubor | Popis |
|---|---|---|
| `pdm_driver` | `src/pdm_driver.vhd` | Generuje clock pro mikrofon (~3.125 MHz), čte 1-bit PDM data |
| `pdm_filter` | `src/pdm_filter.vhd` | Akumulátor – sečte '1' za okno 64 vzorků → hodnota amplitudy |
| `led_bar` | `src/led_bar.vhd` | Převede amplitudu (0–64) na počet rozsvícených LED (0–16) |
| `clk_en` | `src/clk_en.vhd` | Standardní lab komponenta – hodinový enable |
| `top_level` | `src/top_level.vhd` | Propojení všech modulů |

### Příprava .XDC souboru

Namapované piny na Nexys A7-50T:

| Signál | Pin | Popis |
|---|---|---|
| `clk` | E3 | 100 MHz hlavní hodiny |
| `rst` | N17 | Reset (BTNC) |
| `mic_clk_o` | J5 | Clock do MEMS mikrofonu |
| `mic_data_i` | H5 | PDM data z mikrofonu |
| `mic_lr_sel_o` | F5 | Výběr kanálu (L/R), fixně '0' |
| `led_o[0..15]` | H17..T14 | 16x LED |

---

## Lab 2: Unit Design

### pdm_driver

Generuje clock pro mikrofon (dělení 100 MHz / 32 = 3.125 MHz) a čte PDM data na každou náběžnou hranu.

#### Porty

| Port | Směr | Typ | Popis |
|---|---|---|---|
| `clk` | in | std_logic | Hlavní hodiny 100 MHz |
| `rst` | in | std_logic | Synchronní reset, active high |
| `mic_clk_o` | out | std_logic | Clock do mikrofonu |
| `mic_lr_sel_o` | out | std_logic | Výběr kanálu (fixně '0') |
| `mic_data_i` | in | std_logic | PDM data z mikrofonu |
| `pdm_data_o` | out | std_logic | Vzorkovaný PDM bit |
| `pdm_valid_o` | out | std_logic | Pulz = nový platný bit |

#### VHDL kód

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pdm_driver is
    generic (
        G_CLK_DIV : positive := 32
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        mic_clk_o   : out std_logic;
        mic_lr_sel_o: out std_logic;
        mic_data_i  : in  std_logic;
        pdm_data_o  : out std_logic;
        pdm_valid_o : out std_logic
    );
end pdm_driver;

architecture Behavioral of pdm_driver is
    signal cnt     : integer range 0 to G_CLK_DIV-1 := 0;
    signal clk_div : std_logic := '0';
begin
    mic_lr_sel_o <= '0';

    p_clk_div : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt         <= 0;
                clk_div     <= '0';
                pdm_valid_o <= '0';
            else
                pdm_valid_o <= '0';
                if cnt = G_CLK_DIV - 1 then
                    cnt     <= 0;
                    clk_div <= not clk_div;
                    if clk_div = '0' then
                        pdm_data_o  <= mic_data_i;
                        pdm_valid_o <= '1';
                    end if;
                else
                    cnt <= cnt + 1;
                end if;
            end if;
        end if;
    end process;

    mic_clk_o <= clk_div;
end Behavioral;
```

---

### pdm_filter

Jednoduchý decimační akumulátor – počítá '1' v okně 64 PDM bitů. Výsledek odpovídá amplitudě signálu.

#### Porty

| Port | Směr | Typ | Popis |
|---|---|---|---|
| `clk` | in | std_logic | Hlavní hodiny |
| `rst` | in | std_logic | Synchronní reset |
| `pdm_data_i` | in | std_logic | PDM bit ze driveru |
| `pdm_valid_i` | in | std_logic | Platný PDM bit |
| `pcm_data_o` | out | unsigned(6 downto 0) | Výstupní amplituda (0–64) |
| `pcm_valid_o` | out | std_logic | Pulz = nová hodnota amplitudy |

#### VHDL kód

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pdm_filter is
    generic (
        G_WINDOW : positive := 64
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        pdm_data_i  : in  std_logic;
        pdm_valid_i : in  std_logic;
        pcm_data_o  : out unsigned(6 downto 0);
        pcm_valid_o : out std_logic
    );
end pdm_filter;

architecture Behavioral of pdm_filter is
    signal acc : unsigned(6 downto 0) := (others => '0');
    signal cnt : integer range 0 to G_WINDOW-1 := 0;
begin
    p_filter : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                acc         <= (others => '0');
                cnt         <= 0;
                pcm_valid_o <= '0';
            else
                pcm_valid_o <= '0';
                if pdm_valid_i = '1' then
                    if cnt = G_WINDOW - 1 then
                        pcm_data_o  <= acc;
                        pcm_valid_o <= '1';
                        if pdm_data_i = '1' then
                            acc <= to_unsigned(1, 7);
                        else
                            acc <= (others => '0');
                        end if;
                        cnt <= 0;
                    else
                        if pdm_data_i = '1' then
                            acc <= acc + 1;
                        end if;
                        cnt <= cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end Behavioral;
```

#### Simulace (tb_pdm_filter)

*Sem vlož screenshot z Vivado simulátoru po spuštění testbench.*

> **Očekávané chování:** Po 64 validních PDM bitech se objeví pulz `pcm_valid_o = '1'` a `pcm_data_o` odpovídá počtu jedniček v okně.

---

### led_bar

Převede hodnotu amplitudy na počet rozsvícených LED.

#### Porty

| Port | Směr | Typ | Popis |
|---|---|---|---|
| `clk` | in | std_logic | Hlavní hodiny |
| `rst` | in | std_logic | Synchronní reset |
| `level_i` | in | unsigned(6 downto 0) | Amplituda 0–64 |
| `valid_i` | in | std_logic | Nová platná hodnota |
| `led_o` | out | std_logic_vector(15 downto 0) | 16 LED výstupů |

#### VHDL kód

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity led_bar is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        level_i : in  unsigned(6 downto 0);
        valid_i : in  std_logic;
        led_o   : out std_logic_vector(15 downto 0)
    );
end led_bar;

architecture Behavioral of led_bar is
    signal level_scaled : integer range 0 to 16;
begin
    level_scaled <= to_integer(level_i(6 downto 2));

    p_led : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                led_o <= (others => '0');
            elsif valid_i = '1' then
                led_o <= (others => '0');
                for i in 0 to 15 loop
                    if i < level_scaled then
                        led_o(i) <= '1';
                    end if;
                end loop;
            end if;
        end if;
    end process;
end Behavioral;
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
