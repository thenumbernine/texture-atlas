# Texture Atlas generator

[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>
[![Donate via Bitcoin](https://img.shields.io/badge/Donate-Bitcoin-green.svg)](bitcoin:37fsp7qQKU8XoHZGRQvVzQVP8FrEJ73cSJ)<br>

# command-line args:

-	`srcdir=` source directory.  required. only picks pngs.  maybe I'll change that later.
-	`padding=` number of pixels of padding used.  default is 1.
-	`"borderTiled={'path1', 'path2', ...}"` = list of path prefixes to use tiled-border instead of transparent-border in the padding.

# Dependencies:

- https://github.com/thenumbernine/lua-ext
- https://github.com/thenumbernine/vec-ffi-lua
- https://github.com/thenumbernine/lua-image
