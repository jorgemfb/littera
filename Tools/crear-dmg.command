#!/bin/bash
# Doble clic en Finder: ejecuta Tools/crear-dmg.sh en Terminal.
cd "$(dirname "$0")/.." && Tools/crear-dmg.sh
estado=$?
echo "[$(date '+%H:%M:%S')] terminado con código $estado" >> build/crear-dmg.estado
