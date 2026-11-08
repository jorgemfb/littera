#!/bin/bash
# Doble clic en Finder: ejecuta Tools/probar.sh en Terminal.
cd "$(dirname "$0")/.." && Tools/probar.sh
estado=$?
echo "[$(date '+%H:%M:%S')] terminado con código $estado" >> build/probar.estado
