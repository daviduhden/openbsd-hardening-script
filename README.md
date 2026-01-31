# OpenBSD Hardening Script

## Overview

This script automates the hardening of an OpenBSD workstation based on various guides from [Solène Rapenne](https://dataswamp.org/~solene/index.html). Any contribution is highly appreciated.

## Features

- Installs essential packages: anacron, clamav, and (optionally) tor/torsocks or i2pd.
- Enhances user settings for improved security.
- Configures a hardened firewall.
- Lets you choose a single transport (Tor or I2P) for updates (never both).
- Enables the Tor service and configures an onion mirror (optional).
- Enables the I2P (i2pd) service and configures an I2P mirror (optional).
- Disables USB ports (ensure you have a PS/2 keyboard and mouse).
- Activates ClamAV antivirus services and on-access scanning for /home.
- Applies memory allocation hardening configurations.
- Enforces W^X on all filesystems.
- Sets up anacron for periodic tasks.
- Makes shell environment files immutable with `chflags`.
- Configures Xenocara to use CWM by default and fixes screen tearing for Intel video chipsets.

## Requirements

- Must be run as root.
- [OpenBSD operating system](https://www.openbsd.org/faq/faq4.html#Download).

## Usage

1. Clone the repository:
    ```sh
    git clone https://github.com/daviduhden/openbsd-hardening-script.git
    cd openbsd-hardening-script
    ```

2. Make the script executable:
    ```sh
    chmod +x hardening.ksh
    ```

3. Run the script:
    ```sh
    ksh hardening.ksh
    ```

4. Follow the interactive prompts to apply the desired configurations.