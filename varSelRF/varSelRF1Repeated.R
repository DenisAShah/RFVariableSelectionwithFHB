# # Objective(s)
# * 20 RF models from the varSelRF algorithm
# * tune each model, evaluate performance metrics on a test set
# * repeat the train/test split of the data n times, instead of using a single train/test split
# 
# 
# 
# --------------------------------------------------------
# Objects created by this script:
#  varSelRFRep.RData
#
# --------------------------------------------------------


## ----Libraries----------------------------------------------------
library(tidyverse)
library(tidymodels)

library(furrr)  # for setting up parallel processing

library(OptimalCutpoints)
library(PRROC)

library(tictoc)

tidymodels_prefer()

# 
# 
## ----Setup---------------------------------------------------------
# Load the object (m1) containing the information on the models:
# NOTE: This object was created in the script varSelRF0.Rmd
load("varSelRFResII.RData")

# The data on the 20 models:
m2 <- 
   m1 %>%
   dplyr::select(max.vars, max.no.vars, max.fmla, auc.outer) %>%
   tidyr::unnest(cols = auc.outer) %>%
   tibble::rownames_to_column() %>%
   # 20 models:
   dplyr::filter(.estimate >= 0.92, max.no.vars >= 9, max.no.vars <= 14) %>%
   dplyr::rename(vars = max.vars, no.vars = max.no.vars, fmla = max.fmla, auc = .estimate)

# Get the variables (as used across the 20 models):
vars <- 
   m2 %>%  
   dplyr::select(vars) %>%
   tidyr::unnest(cols = vars)


# vars_sub is a character vector of the 32 distinct weather variables (resist is excluded) used among the 20 RF models
vars_sub <-
   vars %>%
   dplyr::distinct() %>%
   dplyr::filter(!var == "resist") %>%
   dplyr::pull(var)

# Load the fhb data matrix:
# Be sure to specify the correct path:
source("../ReadFHBDataset.R")

# The response and set of predictors needed to fit the different RF models:
fhb <-
  X %>%
  # Set up Y as a factor (tidymodels):
  dplyr::mutate(Y = ifelse(S < 10, "Nonepi", "Epi")) %>%
  # The first level is the one you want to predict:
  dplyr::mutate(Y = factor(Y, levels = c("Epi", "Nonepi"))) %>%
  dplyr::select(Y, resist, all_of(vars_sub))


# Number of models:
num_mods <- 20


# A list of the RF model formulas:
fmlas <- purrr::map(1:num_mods, ~purrr::pluck(m2, "fmla", .x))
# Set the names of the model list:
mdl <- stringr::str_c("M", 1:num_mods)
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
   dplyr::mutate(wflow_id = gsub("(_rand_forest)", "", wflow_id))

# Note that mtry upper range needs finalization.
mtry.final <- 
  purrr::map(1:num_mods, ~fhb_set %>%
               extract_workflow(mdl[.x]) %>%
               # NOTE: parameters.workflow()` was deprecated in tune 0.1.6.9003
               # parameters() %>%
               hardhat::extract_parameter_set_dials() %>%
               update(mtry = mtry(c(1, pluck(m2, "no.vars", .x)))))


# Add the mtry parameter ranges to the option column of the workflow set:
for (i in 1:num_mods) {
  fhb_set <- 
    fhb_set %>% 
    option_add(param_info = mtry.final[[i]], id = mdl[i])
}

# Using Bayesian optimization to tune the parameters: 
# Set up the control object:
bayes_ctrl <- control_bayes(no_improve = 20, verbose = TRUE, save_workflow = TRUE)


# Set up the set of metrics to collect (here we'll only look at roc_auc):
roc_res <- metric_set(roc_auc)


# Some cleanup (removal of objects not needed at this point):
rm(list = ls()[!(ls() %in% c("fhb", "fhb_set", "num_mods", "bayes_ctrl", "roc_res"))]) 

# 
# 
## ----Functions----------------------------------------------------------------------------------
eval_tuned_bayes <- function(.mdl, .b_res, fhb_split, ...) {
  # Extract the parameters for the best fit to a model, fit the training data with these tuned parameters, and obtain the predicted probabilities of an epidemic on the test set.
  # NB: this is for a workflowset with the *Bayes* tuning results
  # Args:
  #  .mdl = character string for the model, e.g. "M1"
  #  .b_res = an updated workflow set after tuning
  #  fhb_split = a train/test split of the fhb data
  # NOTE: need the .b_res and fhb_split arguments to pass these objects to the workers
  # Returns:
  #  a tibble with columns for the model, Y and predicted probs on the test data
  #
  # The tuned parameters resulting in the best fit for the model:
  best_results <-
    .b_res %>%
    extract_workflow_set_result(.mdl) %>%
    select_best()
  
  # Extract model, fit to the training set with the tuned parameters, and evaluate on the test set:
  set.seed(1001)     # set seed for reproducibility. RF uses bootstrap sampling in building trees
  .b_res %>% 
    extract_workflow(.mdl) %>%           # return the workflow for model
    finalize_workflow(best_results) %>%  # update the model with the tuning parameters
    last_fit(split = fhb_split)  %>%     # final fit on the training set and evaluation on the test set
    collect_predictions() %>%
    select(Y, prob = .pred_Epi) %>%
    mutate(model = .mdl, .before = Y)
  }  # end function eval_tuned_bayes


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


model_metrics <- function(.seed, num_boot = 25, num_models = num_mods) {
  # Set up the train/test split, tune each of the models on bootstrap resamples on the training data, select the best tuned parameters, refit the model on the train data, and then estimate performance metrics on the test data
  # Args:
  #  .seed = seed for reproducing the train/test split partition
  #  num_boot = number of bootstrap resamples on the training partition
  #  num_models =  number of RF models to be tuned/fit; hard coded by num_mods
  #
  # Returns:
  #   a list of length = length(my.seeds) with the model metrics
  #
  # Set up the data partition:
  set.seed(.seed)
  fhb_split <- initial_split(fhb, prop = 2/3, strata = Y)
  fhb_train <- training(fhb_split)
  fhb_test  <- testing(fhb_split)
  
  # We'll use bootstrap resampling on the training data:
  set.seed(.seed)
  fhb_folds <- 
    bootstraps(fhb_train, strata = Y, times = num_boot)
  
  # Now we are all set up for tuning the models in the workflow set...
  b_res <-
  fhb_set %>%
  workflow_map(
    fn = "tune_bayes",      # the function to run on each workflow in the set. Default = "tune_grid"
    seed = 1503,            # so that each execution of fn uses the same random numbers
    resamples = fhb_folds,  # apply the RF model and formula to these resamples
    initial = 5,            # Semi-random parameters to start
    iter = 30,              # Maximum number of search iterations
    metrics = roc_res,      # the metrics to collect
    control = bayes_ctrl    # used to modify the tuning process
    )
  
  # For each model, obtain the fitted Pr(Epi) on the test data:
  # Note that we have to pass on the objects b_res and fhb_split to the workers in parallel processing:
  bayes_probs <- purrr::map_dfr(stringr::str_c("M", 1:num_models), eval_tuned_bayes, 
                                .b_res = b_res, fhb_split = fhb_split)
  
  # Create nested versions of bayes_probs.  The nested objects provide a convenient way of calculating the performance metrics for each model.

  # For the models tuned via Bayesian optimization:
  bayes_nested <- 
    bayes_probs %>%
    # actual observation as a numeric (Y is a factor for yardstick functions):
    dplyr::mutate(y = ifelse(Y == "Nonepi", 0, 1)) %>%
    dplyr::group_by(model) %>%
    tidyr::nest()
  
  # Apply the function to each of the nested objects:
  bayes_metrics <- CalculateStats(bayes_nested)
  
  return(bayes_metrics)
  }  # end function model_metrics

# 
# 
# ----------------------------------------------------------------------------------
# 
# 
# <!-- # Tune, fit and evaluate the RF models -->
# 
## ----Obtain-metrics----------------------------------------------------------------------
# Seeds for setting up the repeated train/test splits:
my.seeds <- c(1:20)

# Get set up for parallel processing:
# I have 6 cores, so will use 5
plan(list(tweak(multisession, workers = 5), sequential))

tic()
varSelRFRep <- future_map(my.seeds, model_metrics, .options = furrr_options(seed = TRUE))  
# 41818.59 sec = 697 min = 11.6 hr
toc()

plan(sequential)

save(varSelRFRep, file = "varSelRFRep.RData")

# 
# 
## ----Process-results--------------------------------------------------------------------------------------
# Processing the results.
# For each model, estimate the mean and sd of the metric across all n repeats

get_estimates <- function(x, .m) {
  # Estimate the mean and sd for metrics for each model
  # Args:
  #  x = the varSelRFRep object
  #  .m = the unquoted metric name
  # Returns:
  #  a tibble of the summarized metric for each model
  #
  m <- enquo(.m)
  
  dplyr::bind_rows(x) %>%
    dplyr::select(model, !!m) %>%
    dplyr::group_by(model) %>%
    dplyr::summarise(mean = mean(!!m), sd = sd(!!m), .groups = "drop") %>%
    dplyr::mutate(model = factor(model, levels = stringr::str_c("M", 1:20))) %>%  
    dplyr::arrange(model)
}

# Example of use: 
get_estimates(x = varSelRFRep, .m = auc)

# 
# 
# 
# 
# ----------------------------------------------------------------------------------------------
# 
# 
# # Computational environment
## ----SessionInfo-------------------------------------------------
R.Version()$version.string
R.Version()$system
sessionInfo()

