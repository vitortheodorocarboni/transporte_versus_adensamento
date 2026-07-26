# Politica de Ambientes

Este projeto deve usar ambientes globais compartilhados por padrao. A regra
principal e evitar bibliotecas locais criadas por Codex, Claude, Positron ou
RStudio sem uma justificativa explicita.

## R

Biblioteca global padrao:

```text
C:/Users/vitor/R/win-library/4.6
```

Cache global do R:

```text
C:/Users/vitor/R/cache
```

Esses caminhos sao definidos em:

```text
C:/Users/vitor/Documents/.Renviron
```

com:

```text
R_LIBS_USER="C:/Users/vitor/R/win-library/4.6"
R_USER_CACHE_DIR="C:/Users/vitor/R/cache"
```

Regras:

- Antes de instalar um pacote R, verificar se ele ja existe em `R_LIBS_USER`.
- Instalar pacotes recorrentes na biblioteca global, nao em `.Rlib`.
- Nao recriar `.Rlib` neste projeto sem justificativa clara.
- Usar `renv` apenas quando o projeto exigir reprodutibilidade estrita de
  versoes.
- Para `r5r`, usar o Java do sistema, atualmente:

```text
C:/Program Files/Eclipse Adoptium/jdk-25.0.3.9-hotspot/
```

Nao gravar blocos de `rJavaEnv` em `.Rprofile` apontando para caches antigos.

## Python

Python base instalado:

```text
C:/Users/vitor/AppData/Local/Python/bin/python.exe
```

Ambiente global de ciencia de dados:

```text
C:/Users/vitor/.venvs/datascience
```

Esse ambiente deve ser o padrao para Positron, Codex e Claude em analises
Python que nao exijam isolamento por projeto.

O diretorio `C:/Users/vitor/.venvs/datascience/Scripts` deve aparecer primeiro
no `PATH` do usuario. Assim, novos terminais resolvem `python` e `pip` para esse
ambiente compartilhado. O Positron tambem usa esse interpretador como
`python.defaultInterpreterPath` nas configuracoes do usuario.

Regras:

- Antes de instalar um pacote Python, verificar se ele ja existe em
  `C:/Users/vitor/.venvs/datascience`.
- Instalar pacotes gerais com
  `C:/Users/vitor/.venvs/datascience/Scripts/python.exe -m pip install ...`.
- Nao criar `.venv` ou `.python_lib` dentro dos projetos.
- Quando outra versao de Python for indispensavel, criar um ambiente
  compartilhado por runtime ou finalidade em `C:/Users/vitor/.venvs`, fora
  dos projetos e do OneDrive.
- Nao instalar a mesma biblioteca pesada em varios projetos sem motivo.
- Os scripts QGIS devem usar o Python e os pacotes incluidos na instalacao
  corrente do QGIS. O projeto foi validado com QGIS 4.2.0 e Python 3.12.
- Executar scripts QGIS por `qgis/scripts/run_qgis_python.ps1`. O lancador
  encontra a instalacao mais recente em `Program Files`; se necessario,
  definir `QGIS_PYTHON_BAT` com o caminho completo de `python-qgis.bat`.
- O runtime QGIS deve disponibilizar `pyarrow`; nao adicionar caminhos de
  bibliotecas locais ao `sys.path`.

## TinyTeX / Quarto

TinyTeX global padrao:

```text
C:/TinyTeX
```

Binarios no PATH do usuario:

```text
C:/TinyTeX/bin/windows
```

Regras:

- Usar o TinyTeX global para renderizar PDFs em qualquer projeto.
- Nao manter copias locais em `.tools/TinyTeX`.
- O wrapper `scripts/_config/render_quarto_pdf.ps1` usa `xelatex.exe` do
  TinyTeX global e grava caches temporarios em `.quarto-local` para evitar
  problemas de permissao e caminhos longos no Windows.
- Se um pacote LaTeX faltar, instalar/atualizar no TinyTeX global, nao dentro
  do projeto.

## Positron, Codex e Claude

Fluxo padrao:

1. Usar o R global e `R_LIBS_USER` acima.
2. Usar o ambiente Python global quando o projeto nao exigir isolamento.
3. Usar o TinyTeX global para PDFs.
4. Antes de instalar dependencias, consultar os ambientes globais.
5. Se uma instalacao local for necessaria, registrar o motivo no README ou em
   uma nota do projeto.

## Estado Atual

- A antiga `.Rlib` local da dissertacao foi migrada para a biblioteca global de
  R e removida.
- Os scripts ativos da dissertacao foram validados sem `.Rlib`.
- O ambiente Python padrao e `C:/Users/vitor/.venvs/datascience`.
- O TinyTeX padrao e global em `C:/TinyTeX`, com `xelatex.exe` no PATH do
  usuario.
- O projeto QGIS foi validado com QGIS 4.2.0 e o Python 3.12 distribuido com
  essa instalacao; nao ha biblioteca Python dentro do projeto.
- `IGCities` permanece ausente e aparece apenas em material demo antigo em
  `igc/demo_pack/`, nao no pipeline ativo.
