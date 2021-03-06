#' Apply a database caching layer to an arbitrary R function.
#'
#' Requesting data from an API or performing queries can sometimes yield
#' dataframe outputs that are easily cached according to some primary key.
#' This function makes it possible to cache the output along the primary
#' key, while only using the uncached function on those records that
#' have not been computed before.
#'
#' @param uncached_function function. The function to cache.
#' @param key character. A character vector of primary keys. If \code{key} is unnamed,
#'   the user guarantees that \code{uncached_function} has these as formal arguments
#'   and that it returns a data.frame containing columns with at least those
#'   names. For example, if we are caching a function that looks like
#'   \code{function(author) { ... }}, we expect its output to be data.frames
#'   containing an \code{"author"} column with one record for each author.
#'   In this situation, \code{key = "author"}. Otherwise if \code{key} is
#'   a named length 1 vector, the name shall match the uncached_function key
#'   argument, the value shall be matched to at least one of the columns the
#'   returned data.frame contains.
#' @param salt character. The names of the formal arguments of \code{uncached_function}
#'   for which a unique value at calltime should use a different database
#'   table. In other words, if \code{uncached_function} has arguments
#'   \code{id, x, y}, but different kinds of data.frames (i.e., ones with
#'   different types and/or column names) will be returned depending
#'   on the value of \code{x} or \code{y}, then we can set
#'   \code{salt = c("x", "y")} to use a different database table for
#'   each combination of values of \code{x} and \code{y}. For example,
#'   if \code{x} and \code{y} are only allowed to be \code{TRUE} or
#'   \code{FALSE}, with potentially four different kinds of data.frame
#'   outputs, then up to four tables would be created.
#' @param con SQLConnection. Database connection object.
#' @param prefix character. Database table prefix. A different prefix should
#'   be used for each cached function so that there are no table collisions.
#'   Optional, but highly recommended.
#' @param env character. The environment of the database connection if con
#'   is a yaml cofiguration file.
#' @param force logical. If force is \code{TRUE}, force to write to the
#'   caching layer every time the function is called.
#' @return A function with a caching layer that does not call
#'   \code{uncached_function} with already computed records, but retrieves
#'   those results from an underlying database table.
#' @export
## @examples
## \dontrun{
## # These examples assume you have a database connection object
## # (as specified in the DBI package) in a local variable `con`.
##
## # Imagine we have a function that returns a data.frame of information
## # about IMDB titles through their API. It takes an integer vector of
## # IDs and returns a data.frame with an "id" column, with one row for
## # each title. (for example, 111161 would correspond to
## # http://www.imdb.com/title/tt111161/ which is The Shawshank Redemption).
## amazon_info <- function(id) {
##   # Call external API.
## }
##
## # Sending HTTP requests to Amazon and waiting for the response is
## # computationally intensive, so if we ask for some IDs that have
## # already been computed in the past, it would be useful to not
## # make additional HTTP requests for those records. For example,
## # we may want to do some processing on all Amazon titles. However,
## # new records are created each day. Instead of parsing all
## # the historical records on each execution, we would like to only
## # parse new records; old records would be retrieved from a database
## # table that had the same column names as a typical output data.frame
## # of the `amazon_info` function.
## cached_amazon_info <- cachemeifyoucan::cache(amazon_info, key = 'id', con = con)
##
## # By using the `cache` function, we are asking for the following:
## #   (1) If we call `cached_amazon_info` with a vector of integer IDs,
## #       take the subset of IDs that have already been returned from
## #       a previous call to `cached_amazon_info`. Retrieve the data.frame
## #       for these records from an underlying database table.
## #   (2) The remaining IDs (those we have never passed to `cached_amazon_info`
## #       should be fed to the base `amazon_info` function as if we had
## #       called it with this subset. This will yield another data.frame that
## #       was computed using live HTTP requests.
## # The `cached_amazon_info` function will return the union (rbind) of these
## # two data sets as one single data set, as if we had called `amazon_info`
## # by itself. It will also cache the second data set so another identical
## # call to `cached_amazon_info` will not trigger any additional HTTP requests.
##
## ###
## # Salts
## ###
##
## # Imagine our `amazon_info` function is slightly more complicated:
## # instead of always returning the same information about film titles,
## # it has an additional parameter `type` that controls whether we
## # want info about the filmography or about the reviews. The output
## # of this function will still be data.frame's with an `id` column
## # and one row for each title, but the other columns can be different
## # now depending on the `type` parameter.
## amazon_info2 <- function(id, type = 'filmography') {
##   if (identical(type, 'filmography')) { return(amazon_info(id)) }
##   else { return(review_amazon_info(id)) } # Assume we have this other function
## }
##
## # If we wish to cache `amazon_info2`, we need to use different underlying
## # database tables depending on the given `type`. One table may have
## # columns like `num_actors` or `film_length` and the other may have
## # column such as `num_reviews` and `avg_rating`.
## cached_amazon_info2 <- cachemeifyoucan::cache(amazon_info2, key = 'id',
##   salt = 'type', con = con)
##
## # We have told the caching layer to use the `type` parameter as the "salt".
## # This means different values of `type` will use different underlying
## # database tables for caching. It is up to the user to construct a
## # function like `amazon_info2` well so that it always returns a data.frame
## # with exactly the same column names if the `type` parameter is held fixed.
## # The salt should usually consist of a collection of parameters (typically
## # only one, `type` as in this example) that have a small number of possible
## # values; otherwise, many database tables would be created for different
## # values of the salt. Consider the following example.
##
## bad_amazon_filmography <- function(id, actor_id) {
##   # Given a single actor_id and a vector of title IDs,
##   # return information about that actor's role in the film.
## }
## bad_cached_amazon_filmography <-
##   cachemeifyoucan::cache(bad_amazon_filmography, key = 'id',
##     salt = 'actor_id', con = con)
##
## # We will now be creating a separate table each time we call
## # `bad_amazon_filmography` for a different actor!
##
## ###
## # Prefixes
## ###
##
## # It is very important to give the function you are caching a prefix:
## # when it is stored in the database, its table name will be the prefix
## # combined with some string derived from the values in the salt.
##
## cached_review_amazon_info <- cachemeifyoucan::cache(review_amazon_info,
##   key = 'id', con = con)
##
## # Remember our `review_amazon_info` function from an earlier example?
## # If we attempted to cache it without a prefix while also caching
## # the vanilla `amazon_info` function, the same database table would be
## # used for both functions! Since function representation in R is complex
## # and there is no good way in general to determine whether two functions
## # are identical, it is up to the user to determine a good prefix for
## # their function (usually the function's name) so that it does not clash
## # with other database tables.
##
## cached_amazon_info <- cachemeifyoucan::cache(amazon_info,
##   prefix = 'amazon_info', key = 'id', con = con)
## cached_review_amazon_info <- cachemeifyoucan::cache(review_amazon_info,
##   prefix = 'review_amazon_info', key = 'id', con = con)
##
## # We will now use different database tables for these two functions.
##
## ###
## # Advanced features
## ###
##
## # We can use multiple primary keys and salts.
## grab_sql_table <- function(table_name, year, month, dbname = 'default') {
##   # Imagine we have some function that given a table name
##   # and a database name returns a data.frame with aggregate
##   # information about records created in that table from a
##   # given year and month (e.g., ensuring each table has a
##   # created_at column). This function will return a data.frame
##   # with one record for each year-month pair, with at least
##   # the columns "year" and "month".
## }
##
## cached_sql_table <- cachemeifyoucan::cache(grab_sql_table,
##   key = c('year', 'month'), salt = c('table_name', 'dbname'), con = con,
##   prefix = 'sql_table')
##
## # We would like to use a separate table to cache each combination of
## # table_name and dbname. Note that the character vector passed into
## # the `salt` parameter has to exactly match the names of the formal
## # arguments in the initial function, and must also be the name of
## # the columns returned by the data.frame. If these do not agree,
## # you can wrap your function. For example, if the data.frame returned
## # has 'mth' and 'yr' columns, you could instead cache the wrapper:
## wrap_sql_table <- function(table_name, yr, mth, dbname = 'default') {
##   grab_sql_table(table_name = table_name, year = yr, month = mth, dbname = dbname)
## }
## }
cache <- function(uncached_function, key, salt, con, prefix, env, force = FALSE) {
  stopifnot(is.function(uncached_function),
    is.character(prefix), length(prefix) == 1,
    is.character(key), length(key) > 0,
    is.atomic(salt) || is.list(salt),
    is.logical(force))

  cached_function <- new("function")

  # Retain the same formal arguments as the base function.
  formals(cached_function) <- formals(uncached_function)

  # Inject some values we will need in the body of the caching layer.
  environment(cached_function) <-
    list2env(list(`_prefix` = prefix, `_key` = key, `_salt` = salt
      , `_uncached_function` = uncached_function, `_con` = NULL, `_force` = force
      , `_con_build` = c(list(con), if (!missing(env)) list(env))
      , `_env` = if (!missing(env)) env
      ),
      parent = environment(uncached_function))

  build_cached_function(cached_function)
}

build_cached_function <- function(cached_function) {
  # All cached functions will have the same body.
  body(cached_function) <- quote({
    # If a user calls the uncached_function with, e.g.,
    #   fn <- function(x, y) { ... }
    #   fn(1:2), fn(x = 1:2), fn(y = 5, 1:2), fn(y = 5, x = 1:2)
    # then `call` will be a list with names "x" and "y" in all
    # situations.

    raw_call <- match.call()
    call     <- as.list(raw_call[-1]) # Strip function name but retain arguments.

    # Evaluate function call parameters in the calling environment
    for (name in names(call))
      call[[name]] <- eval.parent(call[[name]])

    # Only apply salt on provided values.
    true_salt <- call[intersect(names(call), `_salt`)]

    # Since the values in `call` might be expressions, evaluate them
    # in the calling environment to get their actual values.
    for (name in names(true_salt)) {
      true_salt[[name]] <- eval.parent(true_salt[[name]])
    }

    # The database table to use is determined by the prefix and
    # what values of the salted parameters were used at calltime.
    tbl_name <- cachemeifyoucan:::table_name(`_prefix`, true_salt)

    # Check database connection and reconnect if necessary
    if (is.null(`_con`) || !cachemeifyoucan:::is_db_connected(`_con`)) {
      if (!is.null(`_con_build`[[1]])) {
        `_con` <<- do.call(cachemeifyoucan:::build_connection, `_con_build`)
      } else {
        stop("Cannot re-establish database connection (caching layer)!")
      }
    }

    cachemeifyoucan:::execute(
      cachemeifyoucan:::cached_function_call(`_uncached_function`, call,
        parent.frame(), tbl_name, `_key`, `_con`, `_force`)
    )
  })

  cached_function
}

# A helper function to execute a cached function call.
execute <- function(fcn_call) {
  # Grab the new/old keys
  keys <- fcn_call$call[[fcn_call$key]]
  if (fcn_call$force) { uncached_keys <- keys }
  else {
    uncached_keys <- get_new_key(fcn_call$con, fcn_call$table, keys, fcn_call$output_key)
  }
  cached_keys <- setdiff(keys, uncached_keys)

  uncached_data <- compute_uncached_data(fcn_call, uncached_keys)
  cached_data   <- compute_cached_data(fcn_call, cached_keys)

  # Cache them
  write_data_safely(fcn_call$con, fcn_call$table, uncached_data, fcn_call$output_key)

  data <- plyr::rbind.fill(uncached_data, cached_data)
  ## This seems to cause a bug.
  ## Have to sort to conform with order of keys.
  out <- data[order(match(data[[fcn_call$output_key]], keys), na.last = NA),]
  out
}

match_all <- function(keys, df, column_name) {
  m <- match(keys, df[[column_name]])
  df(order(m))
}

compute_uncached_data <- function(fcn_call, uncached_keys) {
  error_fn(data_injector(fcn_call, uncached_keys, FALSE))
}

compute_cached_data <- function(fcn_call, cached_keys) {
  error_fn(data_injector(fcn_call, cached_keys, TRUE))
}

cached_function_call <- function(fn, call, context, table, key, con, force) {
  # TODO: (RK) Handle keys of length more than 1
  if (is.null(names(key))) {
    output_key <- key
  } else {
    output_key <- unname(key)
    key <- names(key)
  }
  structure(list(fn = fn, call = call, context = context, table = table, key = key,
                 output_key = output_key, con = con, force = force),
    class = 'cached_function_call')
}

data_injector <- function(fcn_call, keys, cached) {
  if (length(keys) == 0) {
    return(data.frame())
  } else if (cached) {
    data_injector_cached(fcn_call, keys)
  } else {
    data_injector_uncached(fcn_call, keys)
  }
}

data_injector_uncached <- function(fcn_call, keys) {
  fcn_call$call[[fcn_call$key]] <- keys
  eval(as.call(append(fcn_call$fn, fcn_call$call)), envir = fcn_call$context)
}

data_injector_cached <- function(fcn_call, keys) {
  sql <- paste("SELECT * FROM", fcn_call$table, "WHERE", fcn_call$output_key, "IN (",
               paste(sanitize_sql(keys), collapse = ', '), ")")
  db2df(dbGetQuery(fcn_call$con, sql),
        fcn_call$con, fcn_call$output_key)
}

sanitize_sql <- function(x) { UseMethod("sanitize_sql") }
sanitize_sql.numeric <- function(x) { x }
sanitize_sql.character <- function(x) {
  paste0("'", gsub("'", "\\'", x, fixed = TRUE), "'")
}

#' Stop on given errors and print corresponding error message.
#'
#' @name error_fn
#' @param data data.frame.
error_fn <- function(data) {
  if (!is.data.frame(data)) {
    stop("Function cached with cachemeifyoucan ",
         "package must return data.frame outputs", call. = FALSE)
  }
  data
}
