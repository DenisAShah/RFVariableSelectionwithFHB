#' # Objective(s)
#' * Selected 20 RF models to further explore based on the results from the varSelRF algorithm
#' * Tuning and performance metrics of these 20 RF models
#' 
#' 
# --------------------------------------------------------
# Data files created by this script:
#  varSelRF1ResGrid.rds
#  varSelRF1ResBayes.rds
#  varSelRF1TestRes.RData
#  varSelRF1TestMetrics.RData
#
# --------------------------------------------------------


## ----Libraries, eval=TRUE, echo=FALSE, message=FALSE--------------------------------------------------------
library(tidyverse)
library(tidymodels)

library(doParallel)

library(OptimalCutpoints)
library(PRROC)

library(kableExtra)

tidymodels_prefer()

#' 
#' 
## ----Setup, eval=TRUE, echo=FALSE, results='hide'-----------------------------------------------------------
# Load the object (m1) containing the information on the models. 
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
   rename(vars = max.vars, no.vars = max.no.vars, fmla = max.fmla, auc = .estimate)

# A check to confirm that all formulas are distinct
m2 %>%
  dplyr::select(fmla) %>%
  dplyr::mutate(foo = map_chr(fmla, toString)) %>%
  dplyr::distinct(foo) %>%
  nrow()


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

#' 
#' 
## ----Helper-functions, eval=TRUE, echo=FALSE----------------------------------------------------------------
# Helper functions (to avoid decimal breaks in the axis tick labels):
# https://stackoverflow.com/questions/61915427/ggplot-integer-breaks-on-facets
my_ceil <- function(x) {
  ceil <- ceiling(max(x))
  ifelse(ceil > 1 & ceil %% 2 == 1, ceil + 1, ceil)
}

my_breaks <- function(x) { 
  ceil <- my_ceil(max(x))
  unique(ceiling(pretty(seq(0, ceil))))
} 

my_limits <- function(x) { 
  ceil <- my_ceil(x[2])
  c(x[1], ceil)
}

#' 
#' 
#' 
#' # Variables used by the models
#' ## No. unique variables
## ----vars-num-unique, eval=TRUE, echo=FALSE-----------------------------------------------------------------
# How many unique variables were used?  Answer = 33
vars %>%
  dplyr::distinct() %>%
  dplyr::arrange(var) %>%
  kable(., row.names = TRUE) %>% 
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE)

#' 
#' 
#' ## No. variables per model
## ----vars-per-model, eval=TRUE, echo=FALSE------------------------------------------------------------------
m2 %>%
  dplyr::select(no.vars) %>%
  dplyr::group_by(no.vars) %>%
  dplyr::summarise(total_count = n()) %>%
  # Easier to visualize...
  # This trick updates the factor levels:
  dplyr::arrange(no.vars) %>%
  dplyr::mutate(no.vars = factor(no.vars, levels = no.vars)) %>%   
  ggplot(aes(x = no.vars, y = total_count)) +
  geom_segment(aes(xend = no.vars, yend = 0)) +
  geom_point(size = 4, colour = "orange") +
  coord_flip() +
  scale_y_continuous(breaks = my_breaks, limits = my_limits) +
  theme_bw() +
  xlab("No. variables") +
  ylab("Frequency")

#' 
#' 
#' ## No. times each variable was used
## ----vars-num-times-used, eval=TRUE, echo=FALSE-------------------------------------------------------------
# How many times was each variable used?
vars %>%
   dplyr::group_by(var) %>%
   dplyr::summarise(total_count = n()) %>%
   # This trick updates the factor levels:
   dplyr::arrange(total_count) %>%
   dplyr::mutate(var = factor(var, levels = var)) %>%   
   ggplot(aes(x = var, y = total_count)) +
   geom_segment(aes(xend = var, yend = 0)) +
   geom_point(size = 1, colour = "orange") +
   coord_flip() +
   theme_bw() +
   xlab("") +
   ylab("Frequency") +
   theme(axis.text.y  = element_text(size = 6),
         axis.title.x = element_text(size = 12, face = "bold"))

#' 
#' 
#' 
#' ----------------------------------------------------------------------------------
#' 
#' 
#' <!-- # Tune, fit and evaluate the RF models -->
#' 
## ----wkflw-Setup, eval=TRUE, echo=FALSE, results='hide'-----------------------------------------------------
# Load the fhb data matrix:
# Be sure to specify the correct path:
source("../ReadFHBDataset.R")

# Some cleanup (removal of objects not needed at this point):
rm(list = ls()[!(ls() %in% c("X", "m2", "vars_sub"))]) 

# The response and set of predictors needed to fit the different RF models:
fhb <-
  X %>%
  # Set up Y as a factor (tidymodels):
  dplyr::mutate(Y = ifelse(S < 10, "Nonepi", "Epi")) %>%
  # The first level is the one you want to predict:
  dplyr::mutate(Y = factor(Y, levels = c("Epi", "Nonepi"))) %>%
  dplyr::select(Y, resist, all_of(vars_sub))


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


# A list of the RF model formulas:
fmlas <- map(1:20, ~pluck(m2, "fmla", .x))
# Set the names of the model list:
mdl <- stringr::str_c("M", 1:20)
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
  map(1:20, ~fhb_set %>%
        extract_workflow(mdl[.x]) %>%
        # NOTE: parameters.workflow()` was deprecated in tune 0.1.6.9003
        # parameters() %>%
        hardhat::extract_parameter_set_dials() %>%
        update(mtry = mtry(c(1, pluck(m2, "no.vars", .x)))))

# A check that mtry.final contains the ranges of mtry for each model:
# NOTE: pull_dials_object()` was deprecated in dials 0.1.0.
# map(1:20, ~mtry.final[[.x]] %>% pull_dials_object("mtry") )
map(1:20, ~mtry.final[[.x]] %>% hardhat::extract_parameter_dials("mtry") )

# Add the mtry parameter ranges to the option column of the workflow set:
for (i in 1:20) {
  fhb_set <- 
    fhb_set %>% 
    option_add(param_info = mtry.final[[i]], id = mdl[i])
}

# Check that the mtry range was set up properly:
pluck(fhb_set, "option", 2, "param_info") %>% pull_dials_object("mtry")

# Now we are all set up for tuning the models in the workflow set...

#' 
#' 
## ----wkflw-grid-tuning, eval=TRUE, echo=FALSE---------------------------------------------------------------
# Here we will use a grid of parameter values for tuning.

# Set up the grid control object:
grid_ctrl <-
   control_grid(
      save_pred = FALSE,
      parallel_over = "everything",
      save_workflow = TRUE
   )

# Set up the set of metrics to collect (here we'll only look at roc_auc):
roc_res <- metric_set(roc_auc)


# For parallel processing:
# doParallel::registerDoParallel()

# Create a cluster object and then register: 
cl <- makePSOCKcluster(4)
doParallel::registerDoParallel(cl)


set.seed(2021)

full_results_time <- 
system.time(
  grid_results <-
  fhb_set %>%
  workflow_map(
    fn = "tune_grid",       # the function to run on each workflow in the set. Default = "tune_grid"
    seed = 1503,            # so that each execution of fn uses the same random numbers
    resamples = fhb_folds,  # apply the RF model and formula to these resamples
    grid = 20,               # grid search on up to 20 automatically-created parameter sets
    metrics = roc_res,       # the metrics to collect
    control = grid_ctrl     # used to modify the tuning process
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

full_results_time  # with 25 bootstraps, grid = 20 and 20 models: 35 min

#' 
#' 
## ----wkflw-bayes-tuning, eval=TRUE, echo=FALSE--------------------------------------------------------------
# Using Bayesian optimization to tune the parameters: 

# Set up the control object:
bayes_ctrl <- control_bayes(no_improve = 20, verbose = TRUE, 
                            parallel_over = "everything", save_workflow = TRUE)

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
unregister_dopar()

# A check that all went well:
pluck(bayes_results, "result", 1)

# How long did it take?
bayes_results_time  # 54 min

#' 
#' 
## ----Save-Tuning-Results, eval=TRUE, echo=FALSE-------------------------------------------------------------
# Saving both objects to a single RData file is 1 GB!!
# save(grid_results, bayes_results, file = "varSelRF1Res.RData")

# Save them separately to rds files:
saveRDS(grid_results, "varSelRF1ResGrid.rds")

saveRDS(bayes_results, "varSelRF1ResBayes.rds")

#' 
#' 
## ----how-to-explore-tuning-results, eval=TRUE, echo=FALSE---------------------------------------------------
# Have a look at the results object:
g_res
# Extract the part that contains the tuning parameters and the estimated metric(s):
pluck(g_res, "result", 1, ".metrics", 1)


## Convenience functions for examining the results:
# rank_results orders the models by some performance metric:
g_res %>% 
   rank_results(rank_metric = "roc_auc") %>% 
   # filter(.metric == "roc_auc") %>% 
   select(model, .config, roc_auc = mean, rank)

# see the tuning parameter results for a specific model:
autoplot(g_res, id = "M2", metric = "roc_auc")

# The mean of the metric for each of the parameter sets over the 25 bootstrap resamples (n):
collect_metrics(g_res) %>%
  # filter(.metric == "roc_auc") %>% 
  select(wflow_id, roc_auc = mean, n, std_err) %>%
  filter(wflow_id == "M1") %>%arrange(desc(roc_auc))


# The tuned parameters resulting in the best fit for model M1:
best_results_M1 <-
  g_res %>%
  extract_workflow_set_result("M1")  %>%
  select_best()
  # select_best(metric = "roc_auc")

# Extract model M1, fit to the training set with the tuned parameters, and evaluate on the test set:
set.seed(1001)
M1_test_results <- 
   g_res %>% 
   extract_workflow("M1") %>%              # return the workflow for model M1
   finalize_workflow(best_results_M1) %>%  # update the model with the tuning parameters
   last_fit(split = fhb_split)             # final fit on the training set and evaluation on the test set

# The metrics on the test data:
collect_metrics(M1_test_results)

# The predicted probability of an epidemic on the test data:
M1_test_results %>% 
  collect_predictions() %>%
  select(Y, prob = .pred_Epi)

# Using the predicted probs to choose a cut-point and calculate downstream statistics (Se, Sp, mcc etc)
# See the code in GeneratetheData.R in the ReBalancing folder

#' 
#' 
## ----process-tuning-results-setup, eval=TRUE, echo=FALSE----------------------------------------------------
# Load the object (m1) containing the information on the models:
load("varSelRFResII.RData")

# Get the variables (as used across as 20 models):
vars_sub <-
   m1 %>%
   dplyr::select(max.vars, max.no.vars, max.fmla, auc.outer) %>%
   tidyr::unnest(cols = auc.outer) %>%
   tibble::rownames_to_column() %>%
   # 20 models:
   dplyr::filter(.estimate >= 0.92, max.no.vars >= 9, max.no.vars <= 14) %>%
   rename(vars = max.vars, no.vars = max.no.vars, fmla = max.fmla, auc = .estimate) %>%  
   dplyr::select(vars) %>%
   tidyr::unnest(cols = vars) %>%
   dplyr::distinct() %>%
   dplyr::pull(var)

# Load the fhb data matrix (make sure the path is correct):
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

# The grid tuning results (assuming you've previously saved them):
g_res <- readRDS("varSelRF1ResGrid.rds")


eval_tuned_grid <- function(.mdl) {
  # Extract the parameters for the best fit to a model, fit the training data with these tuned parameters, and obtain the predicted probabilities of an epidemic on the test set.
  # NB: this is for a workflowset with the *grid* tuning results
  # Args:
  #  .mdl = character string for the model, e.g. "M1"
  # Returns:
  #  a tibble with columns for the model, Y and predicted probs on the test data
  #
  # The tuned parameters resulting in the best fit for the model:
  best_results <-
    g_res %>%
    extract_workflow_set_result(.mdl) %>%
    select_best()
  
  # Extract model, fit to the training set with the tuned parameters, and evaluate on the test set:
  set.seed(1001)     # set seed for reproducibility. RF uses bootstrap sampling in building trees
  g_res %>% 
    extract_workflow(.mdl) %>%           # return the workflow for model
    finalize_workflow(best_results) %>%  # update the model with the tuning parameters
    last_fit(split = fhb_split)  %>%     # final fit on the training set and evaluation on the test set
    collect_predictions() %>%
    select(Y, prob = .pred_Epi) %>%
    mutate(model = .mdl, .before = Y)
  }  # end function eval_tuned_grid


# The Bayes tuning results (assuming they have been saved above):
b_res <- readRDS("varSelRF1ResBayes.rds")


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
## ----test-data-fitted-probs, eval=TRUE, echo=FALSE----------------------------------------------------------
# For each model, obtain the fitted Pr(Epi) on the test data:
grid_probs <- map_dfr(stringr::str_c("M", 1:20), eval_tuned_grid)

bayes_probs <- map_dfr(stringr::str_c("M", 1:20), eval_tuned_bayes)

# Save the objects so that we don't have to rerun the steps:
save(grid_probs, bayes_probs, file = "varSelRF1TestRes.RData")

#' 
#' 
## ----load-test-data-fitted-probs, eval=TRUE, echo=FALSE-----------------------------------------------------
# Load the grid_probs and the bayes_probs objects:
load("varSelRF1TestRes.RData")

#' 
#' 
## ----create-nested, eval=TRUE, echo=FALSE-------------------------------------------------------------------
# Create nested versions of grid_probs and bayes_probs.  The nested objects provide a convenient way of calculating the performance metrics for each model.

# For the models tuned via a grid search:
grid_nested <- 
  grid_probs %>%
  # actual observation as a numeric (Y is a factor for yardstick functions):
  dplyr::mutate(y = ifelse(Y == "Nonepi", 0, 1)) %>%
  dplyr::group_by(model) %>%
  tidyr::nest()

# For the models tuned via Bayesian optimization:
bayes_nested <- 
  bayes_probs %>%
  # actual observation as a numeric (Y is a factor for yardstick functions):
  dplyr::mutate(y = ifelse(Y == "Nonepi", 0, 1)) %>%
  dplyr::group_by(model) %>%
  tidyr::nest()

#' 
#' 
## ----calculate-metrics, eval=TRUE, echo=FALSE---------------------------------------------------------------
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
grid_metrics <- CalculateStats(grid_nested)
bayes_metrics <- CalculateStats(bayes_nested)

# As these will be the two objects we will work on, save them:
save(grid_metrics, bayes_metrics, file = "varSelRF1TestMetrics.RData")

#' 
#' 
#' ----------------------------------------------------------------------------------------------
#' 
#' 
#' # Computational environment
## ----SessionInfo, eval=TRUE, echo=FALSE, results='markup'---------------------------------------------------
R.Version()$version.string
R.Version()$system
sessionInfo()

