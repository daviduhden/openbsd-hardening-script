# OpenBSD Hardening Script

## Overview

This script automates the hardening of an OpenBSD workstation based on various guides from [Solène Rapenne](https://dataswamp.org/~solene/index.html). Any contribution is highly appreciated.

## Features

- Installs essential packages: anacron, tor, torsocks, and clamav.
- Configures user settings to enhance security.
- Sets up a hardened firewall configuration.
- Enables and configures the Tor service.
- Configures the system to use a onion (Tor) mirror for updating the system and installing/updating packages.
- Disables USB ports (Only use this if you have a PS/2 keyboard and mouse).
- Configures ClamAV antivirus and freshclam updater.
- Applies system configuration changes for memory allocation hardening.
- Sets up anacron for periodic tasks.
- Makes shell environment files immutable using chflags.

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