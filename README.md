
-   <a
    href="#into-the-trees-random-forests-for-predicting-fusarium-head-blight-epidemics-of-wheat-in-the-united-states"
    id="toc-into-the-trees-random-forests-for-predicting-fusarium-head-blight-epidemics-of-wheat-in-the-united-states">Into
    the trees: random forests for predicting Fusarium head blight epidemics
    of wheat in the United States</a>
    -   <a href="#data-and-code" id="toc-data-and-code">Data and code</a>
        -   <a href="#the-data" id="toc-the-data">The data</a>
        -   <a href="#schematics" id="toc-schematics"><span>Schematics</span></a>
        -   <a href="#modeling" id="toc-modeling">Modeling</a>
            -   <a href="#boruta" id="toc-boruta"><span>Boruta</span></a>
            -   <a href="#varselrf" id="toc-varselrf"><span>varSelRF</span></a>
            -   <a href="#vsurf" id="toc-vsurf"><span>VSURF</span></a>
            -   <a href="#ensembles" id="toc-ensembles"><span>Ensembles</span></a>
            -   <a href="#shapvalues" id="toc-shapvalues"><span>SHAPvalues</span></a>
            -   <a href="#figures" id="toc-figures"><span>Figures</span></a>
        -   <a href="#manuscript" id="toc-manuscript"><span>Manuscript</span></a>

# Into the trees: random forests for predicting Fusarium head blight epidemics of wheat in the United States

## Data and code

### The data

The [Data directory](Data) contains `.csv` files that are called by the
various scripts. The main dataset (FHB observational data and the
associated weather-based variables) is in
[`FHBdataset.csv`](Data/FHBdataset.csv). This dataset is read by
[`ReadFHBDataset.R`](ReadFHBDataset.R), which is called by other
scripts.

[`VariableSummary.Rmd`](VariableSummary.Rmd) codes for summaries of the
FHB observational data (e.g., how many years or regions were
represented).

The [`VariableMetaData.csv`](Data/VariableMetaData.csv) file contains
other information associated with the weather-based predictors, some of
which is presented in the Tables of the [manuscript
Supplement](Manuscript/Supplement.Rmd).

The [`PreviousModelMetrics.csv`](Data/PreviousModelMetrics.csv) file
contains performance metrics for models reported in [Shah et
al.??2021](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1008831).

### [Schematics](Schematics)

Two flowchart-type diagrams used to show the modeling workflows.

### Modeling

The analysis starts with [Boruta](Boruta).

#### [Boruta](Boruta)

[`BorutaVarSel1.R`](Boruta/BorutaVarSel1.R) runs the [Boruta
algorithm](https://mbq.github.io/Boruta/). Results are saved to `.RData`
files (not uploaded here; see the script).

Having used resampling to run the Boruta algorithm with resampling, look
at the results returned via
[`BorutaVarSel1Smry.Rmd`](Boruta/BorutaVarSel1Smry.Rmd).

#### [varSelRF](varSelRF)

[`varSelRF0.Rmd`](varSelRF/varSelRF0.Rmd) runs the [varSelRF
algorithm](https://github.com/rdiaz02/varSelRF) with the set of
predictors returned by [Boruta](Boruta). Data objects that will be
created with this script are `varSelRFRes.RData` and
`varSelRFResII.RData`.

[`varSelRF1.R`](varSelRF/varSelRF1.R) looks at 20 candidate RF models
stemming from the results output by
[`varSelRF0.Rmd`](varSelRF/varSelRF0.Rmd), and uses
[workflowsets](https://workflowsets.tidymodels.org/) to tune the models,
select the best tuned parameters, and get the probabilities of FHB
epidemics on a test data set. Data objects created:

-   `varSelRF1ResGrid.rds`
-   `varSelRF1ResBayes.rds`
-   `varSelRF1TestRes.RData`
-   `varSelRF1TestMetrics.RData`

none of which are in this repo (because of file size), and which will
have to be done (saved) upon running the script. Same holds for other
`.Rdata` or `.rds` objects created by the other scripts.

#### [VSURF](VSURF)

[`VSURF0.Rmd`](VSURF/VSURF0.Rmd) applies the [VSURF
algorithm](https://github.com/robingenuer/VSURF) to the set of 77
variables selected after running Boruta. This leads to a candidate set
of 38 RF models to explore further. Data objects created:

-   `VSURF0Res.RData`

[`VSURF1.R`](VSURF/VSURF1.R) tunes the models suggested after running
the VSURF algorithm, and gets the performance statistics for the models.
Data objects created:

-   `VSURF1.RData`
-   `VSURF1.rds`
-   `VSURF1TestRes.RData`
-   `VSURF1TestMetrics.RData`

#### [Ensembles](Ensembles)

[`RFEnsembles0.R`](Ensembles/RFEnsembles0.R) ensembles the varSelRF and
VSURF models using stacking via lasso, ridge and elasticnet regression.
Data objects created:

-   `StackedMetrics.RData`

[`RFEnsembles1.Rmd`](Ensembles/RFEnsembles1.Rmd) plots performance
metrics for the models in the current analysis as well as for [models
reported
earlier](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1008831).

[`RFEnsembles2.Rmd`](Ensembles/RFEnsembles2.Rmd) presents some summaries
of the base RF models that were retained by the three metalearners
(lasso, ridge, elasticnet), as well as the metadata on the variables
associated with the base RF models. Data objects created:

-   `StackedRes.RData`

#### [SHAPvalues](SHAPvalues)

[`ShapleyValues.R`](SHAPvalues/ShapleyValues.R) contains code for
[SHapley Additive exPlanations](https://github.com/slundberg/shap) for
one of the RF models.

#### [Figures](Figures)

Contains sub-directories holding `.png` files of Figures produced by the
scripts.

### [Manuscript](Manuscript)

[`ManuscriptFiguresVerIII.Rmd`](Manuscript/ManuscriptFiguresVerIII.Rmd)
is the code for the Figures associated with the paper.

[`Supplement.Rmd`](Manuscript/Supplement.Rmd) contains the code for the
Supplementary pdf file for the paper.
