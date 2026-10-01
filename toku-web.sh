#!/bin/sh
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Birch Point SWE
exec "$(dirname "$(readlink -f "$0")")/toku-container.sh" -i toku-web "$@"
