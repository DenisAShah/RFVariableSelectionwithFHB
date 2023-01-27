
- <a
  href="#into-the-trees-random-forests-for-predicting-fusarium-head-blight-epidemics-of-wheat-in-the-united-states"
  id="toc-into-the-trees-random-forests-for-predicting-fusarium-head-blight-epidemics-of-wheat-in-the-united-states">Into
  the trees: random forests for predicting Fusarium head blight epidemics
  of wheat in the United States</a>
  - <a href="#data-and-modeling-code" id="toc-data-and-modeling-code">Data
    and modeling code</a>
    - <a href="#the-data" id="toc-the-data">The data</a>
    - <a href="#modeling" id="toc-modeling">Modeling</a>
      - <a href="#boruta" id="toc-boruta">Boruta</a>
      - <a href="#varselrf" id="toc-varselrf">varSelRF</a>
      - <a href="#vsurf" id="toc-vsurf">VSURF</a>
      - <a href="#shapvalues" id="toc-shapvalues">SHAPvalues</a>
      - <a href="#figures" id="toc-figures">Figures</a>
  - <a href="#manuscript" id="toc-manuscript">Manuscript</a>
    - <a href="#manuscriptfigures"
      id="toc-manuscriptfigures">ManuscriptFigures</a>
    - <a href="#supplement" id="toc-supplement">Supplement</a>

# Into the trees: random forests for predicting Fusarium head blight epidemics of wheat in the United States

## Data and modeling code

### The data

The [Data directory](Data) contains `.csv` files that are called by the
various scripts. The main dataset (FHB observational data and the
associated weather-based variables) is in
[`FHBdataset.csv`](Data/FHBdataset.csv). This dataset is read by
[`ReadFHBDataset.R`](ReadFHBDataset.R), which is called by other
scripts.

[`DatasetSummary.Rmd`](DatasetSummary.Rmd) codes for some basic
summaries of the FHB observational data (e.g., how many years or regions
were represented) and the weather-based variables.

The [`VariableMetaData.csv`](Data/VariableMetaData.csv) file contains
other information associated with the weather-based predictors, some of
which is presented in the Tables of the [manuscript
Supplement](Supplement/Supplement.Rmd).

The [`PreviousModelMetrics.csv`](Data/PreviousModelMetrics.csv) file
contains performance metrics for models reported in [Shah et
al. 2021](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1008831).

### Modeling

The analysis starts with [Boruta](Boruta).

#### [Boruta](Boruta)

[`PreScreening.R`](Boruta/PreScreening.R) examines the set of
weather-based variables before and after filtering to remove highly
correlated predictors. The filtered set is then input into Boruta.

[`BorutaVarSel1.R`](Boruta/BorutaVarSel1.R) runs the [Boruta
algorithm](https://mbq.github.io/Boruta/). Data objects created:

- `BorutaResSmall.RData`

NOTE: `RData` (and `rds`) objects created by this and the other
following scripts are NOT in the repo, and will have to be created
(saved) upon running the various scripts.

Having used resampling to run the Boruta algorithm with resampling, look
at the results returned via
[`BorutaVarSel1Smry.Rmd`](Boruta/BorutaVarSel1Smry.Rmd).

#### [varSelRF](varSelRF)

[`varSelRF0.Rmd`](varSelRF/varSelRF0.Rmd) runs the [varSelRF
algorithm](https://github.com/rdiaz02/varSelRF) with the set of
predictors returned by [Boruta](Boruta). Data objects created:

- `varSelRFResII.RData`.

[`varSelRF1Single.R`](varSelRF/varSelRF1Single.R) looks at 20 candidate
RF models stemming from the results output by
[`varSelRF0.Rmd`](varSelRF/varSelRF0.Rmd), and uses
[workflowsets](https://workflowsets.tidymodels.org/) to tune the models,
select the best tuned parameters, and get the probabilities of FHB
epidemics on a test data set. A single train/test split is used. Data
objects created:

- `varSelRF1ResBayes.rds`
- `varSelRF1TestRes.RData`
- `varSelRF1TestMetrics.RData`

[`varSelRF1Repeated.R`](varSelRF/varSelRF1Repeated.R) repeats the entire
workflow 20 times, beginning with the train/test split. The emphasis is
on the test performance metrics over the 20 repeats. Data objects
created:

- `varSelRFRep.RData`

#### [VSURF](VSURF)

[`VSURF0.Rmd`](VSURF/VSURF0.Rmd) applies the [VSURF
algorithm](https://github.com/robingenuer/VSURF) to the set of 77
variables selected after running Boruta. This leads to a candidate set
of 38 RF models to explore further. Data objects created:

- `VSURF0Res.RData`

[`VSURF1Single.R`](VSURF/VSURF1Single.R) looks at 38 candidate RF models
stemming from the results output by [`VSURF0.Rmd`](VSURF/VSURF0.Rmd),
and uses [workflowsets](https://workflowsets.tidymodels.org/) to tune
the models, select the best tuned parameters, and get the probabilities
of FHB epidemics on a test data set. A single train/test split is used.
Data objects created:

- `VSURF1.rds`
- `VSURF1TestRes.RData`
- `VSURF1TestMetrics.RData`

[`VSURF1Repeated.R`](VSURF/VSURF1Repeated.R) tunes the models suggested
after running the VSURF algorithm, and gets the performance statistics
for the models. The workflow is repeated 20 times. Data objects created:

- `VSURFRep.RData`

#### [SHAPvalues](SHAPvalues)

[`ShapleyValues.R`](SHAPvalues/ShapleyValues.R) contains code for
[SHapley Additive exPlanations](https://github.com/slundberg/shap) for
one of the RF models. Data objects created:

- `shap.RData`

#### [Figures](Figures)

Contains sub-directories holding `.png` files of Figures produced by the
scripts.

## Manuscript

### [ManuscriptFigures](ManuscriptFigures)

[`ManuscriptFigures.Rmd`](ManuscriptFigures/ManuscriptFigures.Rmd) is
the code for the Figures associated with the paper.

### [Supplement](Supplement)

[`Supplement.Rmd`](Supplement/Supplement.Rmd) contains the code for the
Supplementary pdf file for the paper.
