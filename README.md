# Transporte à periferia ou moradia no centro?

Código, dados selecionados e projeto QGIS da dissertação de mestrado de
Vitor Theodoro Carboni em Políticas Públicas no Insper.

## Visão geral

Este projeto compara duas alternativas de política urbana para São Paulo sob
um orçamento público comum:

1. a operação integral da Linha 6–Laranja do metrô; e
2. uma política de adensamento na região central.

A análise utiliza um modelo quantitativo de equilíbrio espacial baseado em
Ahlfeldt et al. (2015), implementado em R com o pacote `IGC.CSM`. O modelo
representa a localização de residentes e empregos, salários, preços do espaço
construído, acessibilidade, produção e bem-estar nas zonas da Pesquisa
Origem-Destino.

O repositório foi preparado para permitir a inspeção dos dados utilizados, a
reprodução dos resultados centrais e a manutenção dos mapas no QGIS. O texto
da dissertação, apresentações, referências bibliográficas e arquivos de
trabalho não fazem parte deste repositório.

## Conteúdo do repositório

```text
.
├── data/       dados selecionados e resultados necessários à reprodução
├── qgis/       camadas, projeto, scripts e templates cartográficos
├── scripts/    pipeline numerada em R
├── .here       marcador da raiz utilizado pelos scripts
└── README.md
```

O conteúdo versionado está deliberadamente limitado a:

- 41 scripts R e dois auxiliares de renderização;
- 28 arquivos de dados, com aproximadamente 27 MiB;
- o GTFS da SPTrans efetivamente utilizado e seu checksum;
- insumos processados necessários para reexecutar os modelos;
- resultados da situação-base, dos contrafactuais e da comparação de
  políticas;
- camadas de referência, projeto, scripts e templates QGIS.

Não estão incluídos:

- o texto e os arquivos Word/PDF da dissertação;
- apresentações;
- literatura e documentos de referência;
- bases brutas grandes de OD, ITBI, IPTU e OpenStreetMap;
- caches do `r5r`, arquivos temporários e produtos renderizados.

## Escopo da reprodução

Há dois caminhos possíveis.

### Reprodução dos resultados com os dados publicados

Este é o caminho recomendado para verificar a análise. Os arquivos publicados
em `data/processed/` permitem reexecutar:

- a inversão do modelo e o equilíbrio de referência;
- o contrafactual da Linha 6–Laranja;
- o contrafactual de adensamento;
- a comparação espacial de bem-estar;
- a decomposição dos canais de bem-estar;
- a análise de custo-benefício.

Esse caminho preserva os insumos empíricos utilizados na dissertação,
inclusive o GTFS arquivado.

### Reconstrução integral desde as fontes originais

As etapas 01 a 07 e parte das etapas 09 e 10 reconstroem os dados a partir das
fontes originais. Elas envolvem downloads do Metrô-SP, GeoSampa, SPTrans,
Geofabrik/OpenStreetMap, SIDRA, Banco Central e SINAPI.

Algumas dessas fontes são atualizadas ao longo do tempo. Portanto, executar
novamente todos os downloads pode produzir um snapshot diferente daquele
empregado na dissertação. O arquivo `06_01.R`, por exemplo, baixa o GTFS
disponível no momento da execução e requer credenciais válidas no portal de
desenvolvedores da SPTrans. Para reproduzir o snapshot da dissertação, utilize
o GTFS já publicado em:

```text
data/raw/travel_times/r5r_core/sptrans_gtfs.zip
```

## Dados publicados

### Dados brutos preservados

- GTFS da SPTrans utilizado na dissertação e respectivo SHA-256;
- linhas e estações projetadas do metrô obtidas no GeoSampa.

### Dados processados

- base completa e amostra final das zonas OD;
- matriz de tempos de viagem da situação-base;
- parâmetros calibrados do modelo;
- traçado, estações e pontos da Linha 6;
- matriz de viagem contrafactual;
- zonas afetadas e densidade contrafactual da política de uso do solo;
- custo de construção do SINAPI-SP empregado na política.

### Resultados

- inversão do modelo e equilíbrio de referência;
- equilíbrios e variações dos dois contrafactuais;
- comparação espacial entre políticas;
- decomposição do bem-estar;
- variação compensatória e razões benefício-custo.

Os GeoParquets devem ser lidos preservando sua geometria. O helper
`read_geoparquet_sf()` em `scripts/_config/paths.R` converte a geometria
retornada por `arrow` para objetos `sf`.

## Amostra e políticas

A base parte de 343 zonas OD do município de São Paulo. Após a aplicação dos
critérios da dissertação, 18 zonas são excluídas e a amostra do modelo contém
325 zonas.

O contrafactual de transporte representa 15 estações da Linha 6–Laranja, com
23 minutos entre os terminais e headway de 75 segundos no GTFS construído para
a simulação.

O contrafactual de uso do solo aplica um aumento uniforme da densidade de
desenvolvimento a oito zonas centrais. A magnitude é calculada para manter o
mesmo orçamento de R$ 10,3 bilhões atribuído à intervenção de transporte.

Nos resultados arquivados, o ganho agregado de bem-estar é de aproximadamente
0,641% no cenário de transporte e 0,546% no cenário de uso do solo. Esses
valores devem ser recalculados se os dados, parâmetros ou especificações das
políticas forem alterados.

## Requisitos

O projeto foi validado com:

- R 4.6.0;
- `IGC.CSM` 0.3.1;
- Java e pelo menos 8 GB de heap para as rotinas `r5r`;
- QGIS 4.2.0 com Python 3.12 e `pyarrow`.

Pacotes R utilizados na pipeline:

```r
install.packages(c(
  "arrow",
  "curl",
  "data.table",
  "enderecobr",
  "fixest",
  "furrr",
  "future",
  "geocodebr",
  "geodist",
  "geoarrow",
  "geosphere",
  "haven",
  "httr",
  "IGC.CSM",
  "jsonlite",
  "openxlsx2",
  "r5r",
  "rbcb",
  "rJava",
  "rJavaEnv",
  "sf",
  "sidrar",
  "tibble",
  "tidyverse",
  "zip"
))
```

O repositório ainda não utiliza `renv`; as versões completas das dependências
não estão congeladas. A reconstrução do OpenStreetMap em `06_02.R` utiliza
`osmconvert64.exe` e, como está escrita atualmente, é orientada ao Windows.

## Início rápido

Clone o repositório:

```bash
git clone https://github.com/vitortheodorocarboni/transport_land_use.git
cd transport_land_use
```

Execute os comandos a partir da raiz do projeto. Para reproduzir os resultados
centrais usando somente os dados publicados:

```bash
Rscript scripts/08_baseline_scenario/08_01.R
Rscript scripts/08_baseline_scenario/08_02.R
Rscript scripts/09_transport_intervention/09_08.R
Rscript scripts/10_land_use_intervention/10_06.R
Rscript scripts/11_policy_comparison/11_01.R
Rscript scripts/11_policy_comparison/11_02.R
Rscript scripts/11_policy_comparison/11_03.R
```

O arquivo `08_03.R` define a função de variação relativa e é carregado
automaticamente pelos scripts dos contrafactuais.

Os scripts sobrescrevem os Parquets correspondentes em `data/results/`.
Antes de alterar especificações, trabalhe em uma branch separada.

## Pipeline completa

Execute os arquivos em ordem numérica dentro de cada etapa.

| Etapa | Conteúdo |
|---|---|
| `01_od_shapes` | download e tratamento da Pesquisa OD 2023 |
| `02_workers` | massas de trabalhadores residentes e empregados |
| `03_land_area` | área total e área desenvolvível |
| `04_floorspace_prices` | transações ITBI, geocodificação, deflação e preços |
| `05_final_dataset` | integração da base utilizada pelo modelo |
| `06_travel_times` | GTFS, OSM, rede `r5r` e matriz de viagem |
| `07_model_parameters` | estimação e consolidação dos parâmetros |
| `08_baseline_scenario` | inversão e equilíbrio de referência |
| `09_transport_intervention` | construção e solução do cenário da Linha 6 |
| `10_land_use_intervention` | construção e solução do adensamento |
| `11_policy_comparison` | comparação, decomposição e custo-benefício |

Os scripts compartilham as funções de caminho definidas em:

```text
scripts/_config/paths.R
```

O marcador `.here` identifica a raiz, evitando caminhos absolutos específicos
de um computador.

## QGIS

O componente cartográfico está documentado em
[`qgis/README.md`](qgis/README.md).

O projeto principal é:

```text
qgis/projects/everything.qgz
```

As fontes de dados do projeto utilizam caminhos relativos. As camadas locais
em `qgis/layers/` foram obtidas manualmente no GeoSampa ou no IBGE. O mapa-base
do OpenStreetMap é remoto e requer conexão com a internet.

No Windows, os scripts QGIS podem ser executados com:

```powershell
powershell -ExecutionPolicy Bypass -File `
  qgis/scripts/run_qgis_python.ps1 `
  qgis/scripts/03_01_validate_results_symbology.py
```

Consulte o README da pasta para a ordem completa de atualização, validação e
exportação.

## Fontes principais

- Pesquisa Origem-Destino 2023 do Metrô-SP;
- GeoSampa, Prefeitura de São Paulo;
- GTFS e portal Olho Vivo da SPTrans;
- OpenStreetMap/Geofabrik;
- ITBI e IPTU do município de São Paulo;
- SIDRA/IBGE;
- Banco Central do Brasil;
- SINAPI.

## Autoria e citação

Autor: [Vitor Theodoro Carboni](https://github.com/vitortheodorocarboni).

Referência do trabalho:

> Carboni, Vitor Theodoro. *Transporte à periferia ou moradia no centro:
> análise custo-benefício de alternativas para promover acessibilidade urbana
> em São Paulo a partir de um modelo de equilíbrio espacial*. Dissertação de
> mestrado em Políticas Públicas, Insper, 2026.

## Licença

Este repositório ainda não possui uma licença explícita. Até que uma licença
seja adicionada, consulte o autor antes de reutilizar ou redistribuir o código,
os dados ou os produtos cartográficos.
