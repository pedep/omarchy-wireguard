## WireGuard client panel for Omarchy (Quattro)

![alt text](https://github.com/tushar-chauhan/omarchy-wireguard/blob/main/assets/plugin.png "Omarchy WireGuard Plugin")

This plugin discrovers all the `.conf` files present in following folders:
- `~/config/wireguard`
- `~/wireguard`

It won't search in any other directories for wireguard configuration files.

Click on any entry in the discovered connections list to establish the connection.
No `sudo` required.

**Pre-Requisite:**
- `networkmanager`(which provides `nmcli` — already built into Omarchy)

This plugin does **not require** `wireguard-tools`.

`nmcli` handles everything:
- listing configs
- checking status
- importing profiles/configurations

It configures WireGuard interfaces directly through the Linux kernel's native WireGuard module.

_(Note: You can have `wireguard-tools`, if you like running `wg show` manually in your terminal, but the plugin itself does not rely on it.)_
