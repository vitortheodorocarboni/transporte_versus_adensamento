@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0render_quarto_pdf.ps1" %*
