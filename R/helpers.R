alpha <- function(model, data) {
	model(data)[, 1]
}

add_psuedo <- function(data, x) {
	cbind("tmp_crumble_pseudo_y" = x, data)
}

make_folds <- function(data, V, id, strata) {
	if (missing(strata)) {
		if (is.na(id)) {
			folds <- origami::make_folds(data, V = V)
		} else {
			folds <- origami::make_folds(data, cluster_ids = id, V = V)
		}

		if (V > 1) {
			return(folds)
		}

		folds[[1]]$training_set <- folds[[1]]$validation_set
		return(folds)
	}

	binomial <- is_binary(data[[strata]])
	if ((is.na(id) | length(unique(data[[id]])) == nrow(data)) & binomial) {
		strata <- data[[strata]]
		strata[is.na(strata)] <- 2
		folds <- origami::make_folds(data, V = V, strata_ids = strata)
	} else {
		if (is.na(id)) folds <- origami::make_folds(data, V = V)
		else folds <- origami::make_folds(data, cluster_ids = data[[id]], V = V)
	}

	if (V > 1) {
		return(folds)
	}

	folds[[1]]$training_set <- folds[[1]]$validation_set
	folds
}

as_torch <- function(data, device) {
	torch::torch_tensor(as.matrix(data), dtype = torch::torch_float(), device = device)
}

censored <- function(data, cens) {
	# when no censoring return TRUE for all obs
	if (is.na(cens)) {
		return(rep(TRUE, nrow(data)))
	}

	# other wise find censored observations
	return(data[[cens]] == 1)
}

# Function to check if a variable only contains 0, 1, and NA values
is_binary <- function(x) {
	# Remove NA values
	non_na_values <- na.omit(x)

	# Get unique values quickly using unique()
	unique_values <- unique(non_na_values)

	# Check if all non-NA values are either 0 or 1
	if (!all(non_na_values %in% c(0, 1))) {
		return(FALSE)
	}

	TRUE
}

reduce_bind_reorder <- function(x, .f, name1, name2, i) {
	vals <- lapply(x, \(y) y[[name1]]) |>
		lapply(\(z) z[[name2]]) |>
		Reduce(.f, x = _)
	vals[order(i)]
}

recombine_theta <- function(x, folds) {
	ind <- Reduce(c, lapply(folds, function(x) x[["validation_set"]]))
	.f <- function(x) {
		ijkl <- names(x[[1]])

		b_names <- grep("^b", names(x[[1]][[1]]), value = TRUE)
		bs <- lapply(b_names, \(param) sapply(ijkl, \(ijkl) reduce_bind_reorder(x, c, ijkl, param, ind)))
		names(bs) <- b_names

		natural_names <- grep("_natural$", names(x[[1]][[1]]), value = TRUE)
		natural <- lapply(natural_names, \(param) sapply(ijkl, \(ijkl) reduce_bind_reorder(x, c, ijkl, param, ind)))
		names(natural) <- natural_names

		weight_names <- grep("_weights$", names(x[[1]][[1]]), value = TRUE)
		weights <- setNames(
			lapply(weight_names, function(fit) {
				setNames(lapply(ijkl, \(ijkl) lapply(lapply(x, \(y) y[[ijkl]]), \(z) z[[fit]])),
								 ijkl)
			}),
			weight_names
		)

		list(bs = bs,
				 natural = natural,
				 weights = simplify_weights(weights))
	}

	list(theta_n = .f(lapply(x, \(x) x$n)),
			 theta_r = .f(lapply(x, \(x) x$r)))
}

recombine_alpha <- function(x, folds) {
	ind <- Reduce(c, lapply(folds, function(x) x[["validation_set"]]))
	ijkl <- names(x[[1]])
	alpha_names <- grep("^alpha", names(x[[1]][[1]]), value = TRUE)
	setNames(
		lapply(alpha_names,
					 \(param) sapply(ijkl,
					 								\(ijkl) reduce_bind_reorder(x, c, ijkl, param, ind))),
		alpha_names
	)
}

simplify_weights <- function(weights) {
	purrr::map_depth(weights, 3, \(x) data.frame(as.list(x))) |>
		purrr::map_depth(2, \(x) do.call(rbind, x))
}

one_hot_encode <- function(data, vars) {
	tmp <- data[, vars, drop = FALSE]
	as.data.frame(model.matrix(~ ., data = tmp))[, -1, drop = FALSE]
}

no_Z <- function(vars) any(is.na(vars@Z))

is_normalized <- function(x, tolerance = .Machine$double.eps^0.5) {
	# Check if the mean is approximately 1 within the given tolerance
	abs(mean(x) - 1) < tolerance
}

normalize <- function(x) {
	if (is_normalized(x)) return(x)
	x / mean(x)
}
