#' <!-- Run on R 4.1.3 -->
#' 
#' # Objective(s)
#' * we have a set of 39 candidate RF models after running the VSURF algorithm
#' * is there overlap with models that were selected after running the varSelRF algorithm?
#' 
#' 
#' # Notes
#' * the potential overlap in models stemming from varSelRF and VSURF pertains to the models in each group with 9 variables each.  The other varSelRF models have 11 or 14 variables, and the other VSURF models have 6-8 variables
#' 
#' 
#' ---------------------------------------------------------------------------------------
#'  Data files created by this script:
#    VSURF1.RData
#    VSURF1.rds
#    VSURF1TestRes.RData
#    VSURF1TestMetrics.RData
#' ---------------------------------------------------------------------------------------
#' 
#' 
## ----Libraries----------------------------------------------------------------------------------------------
library(tidyverse)
library(tidymodels)
library(ranger)
library(MASS)  # to use robust lm fitting in geom_smooth

library(OptimalCutpoints)
library(PRROC)

library(ggsci)

library(kableExtra)

tidymodels_prefer()

#' 
#' 
## ----Load-fitted-object-------------------------------------------------------------------------------------
# Load the saved object with the VSURF results (see the script `VSURF0.Rmd`):
load("VSURF0Res.RData")

#' 
#' 
#' # Filtering the VSURF models
#' * Goals: distinct, 6-9 variables, auc not less than 0.8
#' * this gives us a candidate set of 38 RF models to evaluate further
#' * still a lot, but we have the code from the varSelRF model evaluations to draw on
#' * we have 9 models listed here with 9 predictors each. From varSelRF, we also have 9 models with 9 predictors each. Are the two sets unique? Or are there overlaps?
#' 
## ----vsurf-filtered-models----------------------------------------------------------------------------------
# This gets the rowid's of duplicate models in the vsurf object:
dups <-
  vsurf %>%
  tibble::rowid_to_column() %>%
  dplyr::select(rowid, indx) %>%
  # Sort the indices:
  dplyr::mutate(sorted = map(indx, sort)) %>%
  # The filtering step identifies the duplicates:
  dplyr::group_by(sorted) %>%
  dplyr::filter(n() > 1) %>%
  # Arrange so that the duplicates are shown together:
  dplyr::arrange(sorted) %>%
  # and filter out every other:
  dplyr::filter(row_number() %% 2 == 1) %>%
  # the rowid's of the duplicates to remove:
  dplyr::pull(rowid)

# Now we filter to a subset of models to pursue further.
# Distinct, 6-9 vars, auc no less than 0.8
vsurf.filtered <-
  vsurf %>%
  tibble::rowid_to_column() %>%
  dplyr::mutate(no_vars = purrr::map(indx, length)) %>%
  dplyr::mutate(vars = map2(splits, indx, function(.splits, .indx) {
    x <- analysis(.splits) %>% select(-Y)
    names(x)[.indx]})) %>%
  dplyr::select(rowid, no_vars, auc, vars) %>%
  tidyr::unnest(cols = c(no_vars, auc)) %>%
  # just easier to call the column auc:
  dplyr::rename(auc = .estimate) %>%
  # apply our filtering criteria:
  dplyr::filter(!rowid %in% dups, no_vars %in% 6:9, auc > 0.8) 


vsurf.filtered %>%
  # arrange for better output representation:
  dplyr::arrange(no_vars, rowid) %>%
  kable(., row.names = TRUE, col.names = c("rowid", "no. vars", "auc", "vars")) %>% 
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE) %>%
  kableExtra::scroll_box(width = "800px", height = "400px")

#' 
#' 
#' # The varSelRF models
#' * there are 20 models (listed below)
#' 
## ----varSelRF-models----------------------------------------------------------------------------------------
# The vars used in the RF models from varSelRF1.Rmd

# Load the object (m1) containing the information on the models:
# (This RData object created upon running the `varSelRF0.Rmd` script)
load("../varSelRF/varSelRFResII.RData")

# The data on the 20 models:
m2 <- 
   m1 %>%
   dplyr::select(max.vars, max.no.vars, max.fmla, auc.outer) %>%
   tidyr::unnest(cols = auc.outer) %>%
   tibble::rownames_to_column() %>%
   # 20 models:
   dplyr::filter(.estimate >= 0.92, max.no.vars >= 9, max.no.vars <= 14) %>%
   rename(vars = max.vars, no.vars = max.no.vars, fmla = max.fmla, auc = .estimate)

# The vars used in each of these models:
m2 %>%
  dplyr::select(vars) %>%
  # Extract the vars from the tibble to a character vector:
  dplyr::mutate(vars = map(vars, ~pluck(.x, "var"))) %>%
  # Sort the vars:
  dplyr::mutate(vars = map(vars, sort)) %>%
  kable(., row.names = TRUE, col.names = c("vars")) %>% 
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE) %>%
  kableExtra::scroll_box(width = "800px", height = "400px")

#' 
#' 
#' # Overlapping models check
#' * among the varSelRF and VSURF models with 9 variables each, are there any overlaps (i.e. same model stemming from varSelRF and VSURF)?
#' * RESULT: there is NO overlap between the two groups
#' * the table lists the 18 models, where the variables have been sorted by name
#' 
## ----varSelRF-vsurf-overlapping-----------------------------------------------------------------------------
# Now, we want to know if any of the VSURF models with 9 vars overlap with the varSelRF models with 9 vars

# The set of varSelRF models with 9 variables each:
varselrf.mods <-
  m2 %>%
  dplyr::filter(no.vars == 9) %>%
  dplyr::select(vars) %>%
  # Extract the vars from the tibble to a character vector:
  dplyr::mutate(vars = map(vars, ~pluck(.x, "var"))) %>%
  dplyr::mutate(algo = "varSelRF", .before = vars) %>%
  # Sort the vars:
  dplyr::mutate(vars = map(vars, sort)) 


# The set of VSURF models with 9 vars each:
vsurf.mods <-
  vsurf.filtered %>%
  dplyr::filter(no_vars == 9) %>%
  dplyr::select(vars) %>%
  dplyr::mutate(algo = "vsurf", .before = vars) %>%
  # Sort the vars:
  dplyr::mutate(vars = map(vars, sort)) 
  

# Bind the two sets of models:
bind_rows(varselrf.mods, vsurf.mods) %>%
  # The filtering step identifies the duplicates:
  dplyr::group_by(vars) %>%
  dplyr::filter(n() > 1)  # there are none

# List out the 18 models:
bind_rows(varselrf.mods, vsurf.mods) %>%
  # Arrange by the vars:
  dplyr::arrange(vars) %>%
  kable(., row.names = TRUE, col.names = c("Algorithm", "vars")) %>% 
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE) %>%
  kableExtra::scroll_box(width = "800px", height = "400px")

#' 
#' 
#' # Overlapping variables
#' * which variables were used by both sets of models (varSelRF and VSURF)?
#' * which were used by varSelRF but not by VSURF (or vice versa)?
#' 
## ----varSelRF-vsurf-overlapping-setup-----------------------------------------------------------------------
# The set of unique vars from the varSelRF models plus the unique vars from the VSURF models:
distinct.vars <- 
  bind_rows(
    # varSelRF distinct variables from the 20 models: there are 33
    m2 %>%
      dplyr::select(vars) %>%
      tidyr::unnest(cols = vars) %>%
      distinct() %>%
      rename(vars = var),
    
    # VSURF distinct variables from the 38 models: there are 27
    vsurf.filtered %>%
      dplyr::select(vars) %>%
      tidyr::unnest(cols = vars) %>%
      distinct()
    ) 

#' 
#' 
#' ## Unique vars used over the 20 varSelRF and 38 VSURF models
## ----varSelRF-vsurf-overlapping-distinct--------------------------------------------------------------------
# How many unique vars used over both sets of models?
distinct.vars %>%
  distinct() %>%  # 35
  arrange(vars) %>%
  kable(., row.names = TRUE, col.names = c("Vars")) %>% 
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE) %>%
  kableExtra::scroll_box(width = "800px", height = "400px")

#' 
#' 
#' ## Vars used by both sets of models
## ----varSelRF-vsurf-overlapping-used-by-both----------------------------------------------------------------
distinct.vars %>%
  count(vars) %>%
  filter(n == 2) %>%  # 25
  kable(., row.names = TRUE, col.names = c("Vars", "Count")) %>% 
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE) %>%
  kableExtra::scroll_box(width = "800px", height = "400px")

#' 
#' 
#' ## Vars used by one set but not the other set
## ----varSelRF-vsurf-overlapping-used-by-one-or-other--------------------------------------------------------
distinct.vars %>%
  count(vars) %>%
  filter(!n == 2) %>%  # 10
  kable(., row.names = TRUE, col.names = c("Vars", "Count")) %>% 
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE)

#' 
#' 
#' ## The non-overlapping vars from the varSelRF models
#' * these appear in the varSelRF models but not in any of the VSURF models
#' 
## ----varSelRF-nonoverlapping--------------------------------------------------------------------------------
# A vector of the non-overlapping variables:
non.overlap.vars <-
  distinct.vars %>%
  count(vars) %>%
  filter(!n == 2) %>%
  pull(vars)

# The eight vars that were in the varSelRF models but not in the VSURF models
m2 %>%
  dplyr::select(vars) %>%
  tidyr::unnest(cols = vars) %>%
  distinct() %>%
  rename(vars = var) %>%
  filter(vars %in% non.overlap.vars) %>%
  arrange(vars) %>%
  kable(., row.names = TRUE, col.names = c("Vars")) %>% 
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE)

#' 
#' ## The non-overlapping vars from the VSURF models
#' * these appear in the VSURF models but not in any of the varSelRF models
#' 
## ----VSURF-nonoverlapping-----------------------------------------------------------------------------------
vsurf.filtered %>%
  dplyr::select(vars) %>%
  tidyr::unnest(cols = vars) %>%
  distinct() %>%
  filter(vars %in% non.overlap.vars) %>%
  arrange(vars) %>%
  kable(., row.names = TRUE, col.names = c("Vars")) %>% 
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE)

#' 
#' 
#' -------------------------------------------------------------------------
#' 
#' 
#' So now we proceed with tuning the VSURF models and estimating their performance statistics.
#' 
## ----model-formulas-----------------------------------------------------------------------------------------
# A list of the RF model formulas:
fmlas <-
  vsurf.filtered %>%
  dplyr::mutate(fmla = map(vars, ~as.formula(paste("Y ~ ", paste(.x, collapse =  "+"))))) %>%
  dplyr::pull(fmla)

# Vector of the predictors used by the models (27 of them):
vars_sub <-
  vsurf.filtered %>%
  dplyr::select(vars) %>%
  tidyr::unnest(cols = vars) %>%
  dplyr::distinct() %>%
  dplyr::pull()

#' 
#' 
## ----wkflw-Setup--------------------------------------------------------------------------------------------
# Load the fhb data matrix:
# NOTE: set the proper paths for your system:
source("../ReadFHBDataset.R")

# The response and set of predictors needed to fit the different RF models:
fhb <-
  X %>%
  # Set up Y as a factor (tidymodels):
  dplyr::mutate(Y = ifelse(S < 10, "Nonepi", "Epi")) %>%
  # The first level is the one you want to predict:
  dplyr::mutate(Y = factor(Y, levels = c("Epi", "Nonepi"))) %>%
  dplyr::select(Y, all_of(vars_sub))


# Set up the data partition:
set.seed(2331)
fhb_split <- initial_split(fhb, prop = 2/3, strata = Y)
fhb_train <- training(fhb_split)
fhb_test  <- testing(fhb_split)

# We'll use bootstrap resampling on the training data:
set.seed(648)
fhb_folds <- 
   bootstraps(fhb_train, strata = Y, times = 25)

# Checks on the no. epi obs in the partitions:
# pluck(fhb_folds, "splits", 1) %>% analysis() %>% count(Y)
# pluck(fhb_folds, "splits", 1) %>% assessment() %>% count(Y)


# Set the names of the model list:
num.mdl <- 1:38
mdl <- stringr::str_c("M", num.mdl)
names(fmlas) <- mdl

# RF engine specification:
# Set up to tune mtry (no. predictors randomly sampled at each split), and min_n (the minimal node size)
# Fix the number of trees at 1000
rf_spec <- rand_forest(mtry = tune(), min_n = tune(), trees = 1000) %>%
  set_mode("classification") %>%
  set_engine("ranger")

# Create a workflow set (each row specifies the model to be fit via RF):
fhb_set <-
  workflow_set(fmlas, list(rf_spec)) %>%
  # Make the workflow ID's simpler: 
   mutate(wflow_id = gsub("(_rand_forest)", "", wflow_id))

# Note that mtry upper range needs finalization.
mtry.final <- 
  map(num.mdl, ~fhb_set %>%
      extract_workflow(mdl[.x]) %>%
      hardhat::extract_parameter_set_dials() %>%
      update(mtry = mtry(c(1, pluck(vsurf.filtered, "no_vars", .x)))))

# A check that mtry.final contains the ranges of mtry for each model:
map(num.mdl, ~mtry.final[[.x]] %>% hardhat::extract_parameter_dials("mtry") )

# Add the mtry parameter ranges to the option column of the workflow set:
for (i in num.mdl) {
  fhb_set <- 
    fhb_set %>% 
    option_add(param_info = mtry.final[[i]], id = mdl[i])
}

# Check that the mtry range was set up properly:
pluck(fhb_set, "option", 2, "param_info") %>% pull_dials_object("mtry")

# Now we are all set up for tuning the models in the workflow set...
rm(list = ls()[!(ls() %in% c(str_subset(ls(), "^fhb"), "rf_spec", "vsurf.filtered"))]) 

#' 
#' 
## ----wkflw-bayes-tuning-------------------------------------------------------------------------------------
# Using Bayesian optimization to tune the parameters...

# Set up the set of metrics to collect (here we'll only look at roc_auc):
roc_res <- metric_set(roc_auc)

# Set up the control object:
bayes_ctrl <- control_bayes(no_improve = 20, verbose = TRUE, 
                            parallel_over = "everything", save_workflow = TRUE)

# Create a cluster object and then register: 
cl <- makePSOCKcluster(4)
doParallel::registerDoParallel(cl)
set.seed(2021)

bayes_results_time <- 
system.time(
bayes_results <-
  fhb_set %>%
  workflow_map(
    fn = "tune_bayes",      # the function to run on each workflow in the set. Default = "tune_grid"
    seed = 1503,            # so that each execution of fn uses the same random numbers
    resamples = fhb_folds,  # apply the RF model and formula to these resamples
    initial = 5,            # Semi-random parameters to start. NB: tune_grid results will not work here...
    iter = 30,              # Maximum number of search iterations
    metrics = roc_res,      # the metrics to collect
    control = bayes_ctrl    # used to modify the tuning process
    )
)

stopCluster(cl)

# NB: even with stopCluster, you may still get an error message when trying to run lines below:
# "Error in summary.connection(connection) : invalid connection"
# The solution is the function below.
# See https://stackoverflow.com/questions/25097729/un-register-a-doparallel-cluster
unregister_dopar <- function() {
  env <- foreach:::.foreachGlobals
  rm(list=ls(name=env), pos=env)
}

unregister_dopar()

# A check that all went well:
pluck(bayes_results, "result", 1)

# How long did it take?
bayes_results_time  # 96 min

# These both take up about the same storage (large 1.5 GB files)
save(bayes_results, file = "VSURF1.RData")
saveRDS(bayes_results, "VSURF1.rds")

#' 
#' 
## ----process-tuning-results-setup---------------------------------------------------------------------------
# Load the saved object (i.e., vsurf) with the VSURF results (from the `VSURF0.Rmd` script):
load("VSURF0Res.RData")

# NOTE: Here, run the code in the chunk `vsurf-filtered-models` to set up the filtered set of models.
# You want the object vsurf.filtered
# This gets the rowid's of duplicate models in the vsurf object:
dups <-
  vsurf %>%
  tibble::rowid_to_column() %>%
  dplyr::select(rowid, indx) %>%
  # Sort the indices:
  dplyr::mutate(sorted = map(indx, sort)) %>%
  # The filtering step identifies the duplicates:
  dplyr::group_by(sorted) %>%
  dplyr::filter(n() > 1) %>%
  # Arrange so that the duplicates are shown together:
  dplyr::arrange(sorted) %>%
  # and filter out every other:
  dplyr::filter(row_number() %% 2 == 1) %>%
  # the rowid's of the duplicates to remove:
  dplyr::pull(rowid)

# Now we filter to a subset of models to pursue further.
# Distinct, 6-9 vars, auc no less than 0.8
vsurf.filtered <-
  vsurf %>%
  tibble::rowid_to_column() %>%
  dplyr::mutate(no_vars = purrr::map(indx, length)) %>%
  dplyr::mutate(vars = map2(splits, indx, function(.splits, .indx) {
    x <- analysis(.splits) %>% select(-Y)
    names(x)[.indx]})) %>%
  dplyr::select(rowid, no_vars, auc, vars) %>%
  tidyr::unnest(cols = c(no_vars, auc)) %>%
  # just easier to call the column auc:
  dplyr::rename(auc = .estimate) %>%
  # apply our filtering criteria:
  dplyr::filter(!rowid %in% dups, no_vars %in% 6:9, auc > 0.8) 


vsurf.filtered %>%
  # arrange for better output representation:
  dplyr::arrange(no_vars, rowid) %>%
  kable(., row.names = TRUE, col.names = c("rowid", "no. vars", "auc", "vars")) %>% 
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE) %>%
  kableExtra::scroll_box(width = "800px", height = "400px")

# The number of models:
num.mdl <- 1:38

# Vector of the predictors used by the models (27 of them):
vars_sub <-
  vsurf.filtered %>%
  dplyr::select(vars) %>%
  tidyr::unnest(cols = vars) %>%
  dplyr::distinct() %>%
  dplyr::pull()

# Load the fhb data matrix:
source("../ReadFHBDataset.R")

# The response and set of predictors needed to fit the different RF models:
fhb <-
  X %>%
  # Set up Y as a factor (tidymodels):
  dplyr::mutate(Y = ifelse(S < 10, "Nonepi", "Epi")) %>%
  # The first level is the one you want to predict:
  dplyr::mutate(Y = factor(Y, levels = c("Epi", "Nonepi"))) %>%
  dplyr::select(Y, all_of(vars_sub))

# Set up the data partition:
set.seed(2331)
fhb_split <- initial_split(fhb, prop = 2/3, strata = Y)

# Some cleanup (removal of objects not needed at this point):
rm(list = ls()[!(ls() %in% c("fhb_split"))]) 

# The Bayes tuning results:
b_res <- readRDS("VSURF1.rds")


eval_tuned_bayes <- function(.mdl) {
  # Extract the parameters for the best fit to a model, fit the training data with these tuned parameters, and obtain the predicted probabilities of an epidemic on the test set.
  # NB: this is for a workflowset with the *Bayes* tuning results
  # Args:
  #  .mdl = character string for the model, e.g. "M1"
  # Returns:
  #  a tibble with columns for the model, Y and predicted probs on the test data
  #
  # The tuned parameters resulting in the best fit for the model:
  best_results <-
    b_res %>%
    extract_workflow_set_result(.mdl) %>%
    select_best()
  
  # Extract model, fit to the training set with the tuned parameters, and evaluate on the test set:
  set.seed(1001)     # set seed for reproducibility. RF uses bootstrap sampling in building trees
  b_res %>% 
    extract_workflow(.mdl) %>%           # return the workflow for model
    finalize_workflow(best_results) %>%  # update the model with the tuning parameters
    last_fit(split = fhb_split)  %>%     # final fit on the training set and evaluation on the test set
    collect_predictions() %>%
    select(Y, prob = .pred_Epi) %>%
    mutate(model = .mdl, .before = Y)
  }  # end function eval_tuned_bayes

#' 
#' 
## ----test-data-fitted-probs---------------------------------------------------------------------------------
# For each model, obtain the fitted Pr(Epi) on the test data:
bayes_probs <- map_dfr(stringr::str_c("M", num.mdl), eval_tuned_bayes)

# Save the objects so that we don't have to rerun the steps:
save(bayes_probs, file = "VSURF1TestRes.RData")

#' 
#' 
## ----load-test-data-fitted-probs----------------------------------------------------------------------------
# Load the grid_probs and the bayes_probs objects:
load("VSURF1TestRes.RData")

#' 
#' 
## ----create-nested------------------------------------------------------------------------------------------
# Create nested versions of bayes_probs.  The nested objects provide a convenient way of calculating the performance metrics for each model.

# For the models tuned via Bayesian optimization:
bayes_nested <- 
  bayes_probs %>%
  # actual observation as a numeric (Y is a factor for yardstick functions):
  dplyr::mutate(y = ifelse(Y == "Nonepi", 0, 1)) %>%
  dplyr::group_by(model) %>%
  tidyr::nest()

#' 
#' 
## ----calculate-metrics--------------------------------------------------------------------------------------
CalculateStats <- function(.x) {
  # calculate the statistics from the predicted probs for each model:
  # Args:
  #  .x = a nested object containing predicted probs for each model (e.g. grid_nested)
  # Returns:
  #  a tibble of estimated metrics
  #
  .x %>%
    # number of rows:
    dplyr::mutate(n = purrr::map_dbl(data, ~nrow(.x))) %>%
    # data frame of the actual values and predicted probs for input into OptimalCutpoints:
    dplyr::mutate(df = purrr::map(data, ~{data.frame(id = 1:nrow(.x), actual = .x$y, prob = .x$prob)})) %>%
    # get the cutpoint based on Youden:
    dplyr::mutate(oc = purrr::map(df, ~OptimalCutpoints::optimal.cutpoints(X = prob ~ actual, tag.healthy = 0, methods = "Youden", data = .x))) %>%
    dplyr::mutate(cp.val = purrr::map_dbl(oc, ~pluck(.x, "Youden", 1, "optimal.cutoff", "cutoff", 1))) %>%
    # The actual class:
    dplyr::mutate(actual = purrr::map(data, "y")) %>%
    # The predicted class:
    dplyr::mutate(pred = purrr::map2(data, cp.val, .f = function(.data, .cp) {z = as.data.frame(.data) %>%
      dplyr::pull(prob); ifelse(z <= .cp, 0, 1)})) %>%
    # Set actual and pred as factors (required for `yardstick`):
    dplyr::mutate(actual.f = purrr::map(actual, ~factor(.x, levels = c(1, 0)))) %>%
    dplyr::mutate(pred.f = purrr::map(pred, ~factor(.x, levels = c(1, 0)))) %>%
    dplyr::mutate(data.f = purrr::map2(actual.f, pred.f, ~{data.frame(truth = .x, estimate = .y)})) %>%
    # ROC_AUC:
    dplyr::mutate(auc = purrr::map_dbl(data, ~{yardstick::roc_auc(.x, truth = Y, prob, options = list(smooth = TRUE)) %>%
        dplyr::pull(.estimate)})) %>%
    # precision-recall area under curve:
    dplyr::mutate(prauc = purrr::map_dbl(data, ~{PRROC::pr.curve(scores.class0 = .x$prob, weights.class0 = .x$y) %>% purrr::pluck("auc.integral")})) %>%
    
    # F-Measure:
    dplyr::mutate(F1 = purrr::map_dbl(data.f, ~{yardstick::f_meas(.x, truth = truth, estimate = estimate) %>%
        dplyr::pull(.estimate)})) %>%
    # Kappa:
    dplyr::mutate(kap = purrr::map_dbl(data.f, ~{yardstick::kap(.x, truth = truth, estimate = estimate) %>%
        dplyr::pull(.estimate)})) %>%
    # Detection prevalence:
    dplyr::mutate(dp = purrr::map_dbl(data.f, ~{yardstick::detection_prevalence(.x, truth = truth, estimate = estimate) %>%
        dplyr::pull(.estimate)})) %>%
    # mcc:
    dplyr::mutate(mcc = purrr::map_dbl(data.f, ~{yardstick::mcc(.x, truth = truth, estimate = estimate) %>%
        dplyr::pull(.estimate)})) %>%
    # Brier score:
    dplyr::mutate(Brier = map_dbl(data, ~sum((.x$prob - .x$y)^2)/nrow(.x))) %>%
    
    # true positives count:
    dplyr::mutate(TP = purrr::map2_dbl(actual, pred, ~{sum(.x == 1 & .y == 1)})) %>%
    # false positives count:
    dplyr::mutate(FP = purrr::map2_dbl(actual, pred, ~{sum(.x == 0 & .y == 1)})) %>%
    # false negatives count:
    dplyr::mutate(FN = purrr::map2_dbl(actual, pred, ~{sum(.x == 1 & .y == 0)})) %>%
    # true negatives count:
    dplyr::mutate(TN = purrr::map2_dbl(actual, pred, ~{sum(.x == 0 & .y == 0)})) %>%
    # All negatives:
    dplyr::mutate(AN = purrr::map2_dbl(TN, FP, ~{.x + .y})) %>%
    # All positives:
    dplyr::mutate(AP = purrr::map2_dbl(TP, FN, ~{.x + .y})) %>%
    
    # Misclassification rate:
    dplyr::mutate(mr = purrr::pmap_dbl(list(FP, FN, n), ~{(..1 + ..2)/..3})) %>%
    # Accuracy:
    dplyr::mutate(acc = purrr::map_dbl(mr, ~{1 - .x})) %>%
    # No information rate:
    dplyr::mutate(nir = purrr::pmap_dbl(list(TN, FP, n), ~{(..1 + ..2)/..3})) %>%
    
    # sensitivity:
    dplyr::mutate(Se = purrr::map2_dbl(TP, FN, ~{.x/(.x + .y)})) %>%
    # specificity:
    dplyr::mutate(Sp = purrr::map2_dbl(TN, FP, ~{.x/(.x + .y)})) %>%
    # YI/ifd/K:
    dplyr::mutate(ifd = purrr::map2_dbl(Se, Sp, ~{.x + .y - 1})) %>%
    # G-Mean:
    dplyr::mutate(GM = purrr::map2_dbl(Se, Sp, ~{sqrt(.x*.y)})) %>%
    # The average of Se and Sp (balanced accuracy):
    dplyr::mutate(bac = purrr::map2_dbl(Se, Sp, ~{(.x + .y)/2})) %>%
    # Power metric (PM; Lopes et al. 2017):
    dplyr::mutate(PM = purrr::map2_dbl(Se, Sp, ~{.x/(1 + .x - .y)})) %>%
    # discriminant power:
    dplyr::mutate(dpow = purrr::map2_dbl(Se, Sp, ~{(sqrt(3)/pi)*(log(.x/(1-.x)) + log(.y/(1-.y)))})) %>%
    # Positive diagnostic likelihood ratio:
    dplyr::mutate(DLR.pos = purrr::map2_dbl(Se, Sp, ~{.x/(1 - .y)})) %>%
    # Negative diagnostic likelihood ratio:
    dplyr::mutate(DLR.neg = purrr::map2_dbl(Se, Sp, ~{(1 - .x)/.y})) %>%
    # Diagnostic odds ratio (DOR):
    dplyr::mutate(DOR = purrr::map2_dbl(DLR.pos, DLR.neg, ~{.x/.y})) %>%
    # Prevalence threshold (PT):
    dplyr::mutate(PT = purrr::map2_dbl(Se, Sp, ~{(-1 + .y + sqrt(.x - .y*.x))/(-1 + .y + .x)})) %>%
    # positive predictive value (ppv) = Pr(D1|T1) = precision:
    dplyr::mutate(ppv = purrr::map2_dbl(TP, FP, ~{.x/(.x + .y)})) %>%
    # negative predictive value (npv) = Pr(D0|T0):
    dplyr::mutate(npv = purrr::map2_dbl(TN, FN, ~{.x/(.y + .x)})) %>%
    # markedness aka Powers (2011):
    dplyr::mutate(mkd = purrr::map2_dbl(ppv, npv, ~{.x + .y - 1})) %>%
    # Fowlkes–Mallows index:
    dplyr::mutate(FM = purrr::map2_dbl(ppv, Se, ~{sqrt(.x*.y)})) %>%
    
    # The normalized prediction-realization table (next 4 lines):
    dplyr::mutate(TPn = purrr::pmap_dbl(list(actual, pred, n), ~{sum(..1 == 1 & ..2 == 1)/..3})) %>%
    dplyr::mutate(FPn = purrr::pmap_dbl(list(actual, pred, n), ~{sum(..1 == 0 & ..2 == 1)/..3})) %>%
    dplyr::mutate(FNn = purrr::pmap_dbl(list(actual, pred, n), ~{sum(..1 == 1 & ..2 == 0)/..3})) %>%
    dplyr::mutate(TNn = purrr::pmap_dbl(list(actual, pred, n), ~{sum(..1 == 0 & ..2 == 0)/..3})) %>%
    
    # Prior probability of epidemic:
    dplyr::mutate(PrD1 = purrr::map2_dbl(TPn, FNn, ~{.x + .y})) %>%
    # Prior probability of non-epidemic:
    dplyr::mutate(PrD0 = purrr::map_dbl(PrD1, ~{1 - .x})) %>%
    # Probability of an epidemic prediction:
    dplyr::mutate(PrT1 = purrr::map2_dbl(TPn, FPn, ~{.x + .y})) %>%
    # Probability of a non-epidemic prediction:
    dplyr::mutate(PrT0 = purrr::map2_dbl(FNn, TNn, ~{.x + .y})) %>%
    # Information quantity (entropy) H(D):
    dplyr::mutate(HD = purrr::map2_dbl(PrD1, PrD0, ~{-(.x*log(.x) + .y*log(.y))})) %>%
    # Information quantity (entropy) H(T):
    dplyr::mutate(HT = purrr::map2_dbl(PrT1, PrT0, ~{-(.x*log(.x) + .y*log(.y))})) %>%
    # Information quantity (joint entropy) H(D,T):
    dplyr::mutate(HDT = purrr::pmap_dbl(list(TPn, FPn, FNn, TNn), ~{-(..1*log(..1) + ..2*log(..2) + ..3*log(..3) + ..4*log(..4))})) %>%
    # Expected mutual information (I_M(D,T)):
    dplyr::mutate(IM = purrr::pmap_dbl(list(HD, HT, HDT), ~{..1 + ..2 - ..3})) %>%
    # Conditional entropy H(D|T):
    dplyr::mutate(HDcT = purrr::map2_dbl(HD, IM, ~{.x - .y})) %>%
    # Normalized expected mutual information, (equiv. to McFadden's R2) Hughes et al. (2019):
    dplyr::mutate(IMN = purrr::map2_dbl(IM, HD, ~{.x/.y})) %>%
    
    # NMI measure of Forbes (1995) writing out this way because had problems with the ~ and ..1 notation
    # Also, using log2 instead of log -- seems better numerical accuracy. Same result.
    dplyr::mutate(NMI = purrr::pmap_dbl(list(TP, FP, FN, TN, n), function(.TP, .FP, .FN, .TN, .n) {1 - (-.TP*log2(.TP) - .FP*log2(.FP) - .FN*log2(.FN) - .TN*log2(.TN) + (.TP+.FP)*log2(.TP+.FP) + (.FN+.TN)*log2(.FN+.TN))/(.n*log2(.n) - ((.TP+.FN)*log2(.TP+.FN) + (.FP+.TN)*log2(.FP+.TN)))})) %>%
    
    # MCEN:
    dplyr::mutate(S = purrr::pmap_dbl(list(TP, FP, FN, TN), ~{..1 + ..2 + ..3 + ..4})) %>%
    dplyr::mutate(MCEN = purrr::pmap_dbl(list(S, TP, TN, FP, FN), ~{(2*(..5+..4)*log2((..1-..3)*(..1-..2)))/(3*..1 + ..5+..4) - (4*(..5*log2(..5) + ..4*log2(..4)))/(3*..1 + ..5 +..4)})) %>%
    # The inverse of MCEN:
    dplyr::mutate(imcen = purrr::map_dbl(MCEN, ~{1/.x})) %>%
    
    # Keep only the columns you need:
    dplyr::select(model, cp.val, auc:Brier, mr:FM, IMN, NMI, MCEN, imcen) %>%
    
    tidyr::unnest(cols = where(is.double)) %>%
    dplyr::ungroup()
  }  # end function CalculateStats

# Apply the function to each of the nested objects:
bayes_metrics <- CalculateStats(bayes_nested)

# As these will be the two objects we will work on, save them:
save(bayes_metrics, file = "VSURF1TestMetrics.RData")

#' 
#' 
#' ----------------------------------------------------------------------------------------------
#' 
#' 
#' # Computational environment
## ----SessionInfo--------------------------------------------------------------------------------------------
R.Version()$version.string
R.Version()$system
sessionInfo()

