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
zde bude schema hanz
```
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
library ieee;
  use ieee.std_logic_1164.all;

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

architecture Behavioral of debounce is

    signal ce_sample          : std_logic;
    signal shift_reg          : std_logic_vector(3 downto 0) := (others => '0');
    signal sync0, sync1       : std_logic := '0';
    signal debounced, delayed : std_logic := '0';

    component clk_en is
        generic ( G_MAX : positive );
        port ( clk : in std_logic; rst : in std_logic; ce : out std_logic );
    end component;

begin

    clk_en_inst : clk_en
        generic map ( G_MAX => G_MAX )
        port map ( clk => clk, rst => rst, ce => ce_sample );

    p_debounce : process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sync0     <= '0';
                sync1     <= '0';
                shift_reg <= (others => '0');
                debounced <= '0';
                delayed   <= '0';
                btn_o     <= '0';
            else
                sync0 <= btn_i;
                sync1 <= sync0;
                if ce_sample = '1' then
                    shift_reg <= shift_reg(2 downto 0) & sync1;
                end if;
                if    shift_reg = "1111" then debounced <= '1';
                elsif shift_reg = "0000" then debounced <= '0';
                end if;
                delayed <= debounced;
                if debounced = '1' and delayed = '0' then
                    btn_o <= '1';
                else
                    btn_o <= '0';
                end if;
            end if;
        end if;
    end process p_debounce;

end architecture Behavioral;
```

---

---
zde bude pdm_driver i s vhdl kodem aji porty tam vlozi hanz
---
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
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity sensitivity_ctrl is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        btn_up_i : in  std_logic;
        btn_dn_i : in  std_logic;
        window_o : out std_logic_vector(7 downto 0)
    );
end entity sensitivity_ctrl;

architecture Behavioral of sensitivity_ctrl is

    signal sig_window : unsigned(7 downto 0) := to_unsigned(128, 8);

begin

    p_sensitivity : process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sig_window <= to_unsigned(128, 8);
            else
                if btn_up_i = '1' and sig_window > 32 then
                    sig_window <= sig_window - 32;
                elsif btn_dn_i = '1' and sig_window < 224 then
                    sig_window <= sig_window + 32;
                end if;
            end if;
        end if;
    end process p_sensitivity;

    window_o <= std_logic_vector(sig_window);

end architecture Behavioral;
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
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

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

architecture Behavioral of pdm_filter is

    signal sig_acc : unsigned(7 downto 0) := (others => '0');
    signal sig_cnt : unsigned(7 downto 0) := (others => '0');

begin

    p_filter : process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sig_acc     <= (others => '0');
                sig_cnt     <= (others => '0');
                pcm_data_o  <= (others => '0');
                pcm_valid_o <= '0';
            else
                pcm_valid_o <= '0';

                if pdm_valid_i = '1' then
                    if sig_cnt >= unsigned(window_i) - 1 then
                        pcm_data_o  <= std_logic_vector(sig_acc);
                        pcm_valid_o <= '1';
                        sig_cnt     <= (others => '0');
                        if pdm_data_i = '1' then
                            sig_acc <= to_unsigned(1, 8);
                        else
                            sig_acc <= (others => '0');
                        end if;
                    else
                        if pdm_data_i = '1' then
                            sig_acc <= sig_acc + 1;
                        end if;
                        sig_cnt <= sig_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process p_filter;

end architecture Behavioral;
```

#### Simulace (tb_pdm_filter)

<img width="1482" height="830" alt="image" src="https://github.com/user-attachments/assets/0e6ff2f1-5520-4856-bd2f-f80278f6f72d" />

*Obr. 1: Behaviorální simulace modulu pdm_filter. Signál pcm_data postupně nabývá hodnot:
0x00 (ticho), 0x20 (střední hlasitost), 0x3E (hlasitý zvuk) a 0x11 po změně okna na 32 vzorků.*

---
