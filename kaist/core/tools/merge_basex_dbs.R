################################################################################
# merge_basex_dbs.R: list the scenarios in GCAM BaseX databases and copy a
# chosen set of them into one new database. Needs only java and the BaseX jar
# (no ModelInterface, no rgcam).
#
# Usage (from the repo root):
#   Rscript kaist/core/tools/merge_basex_dbs.R list <folder> [<folder> ...]
#   Rscript kaist/core/tools/merge_basex_dbs.R merge <new db folder> <folder>[:<scenario name>] ... [--pick 1,3,5 | --interactive]
#   Options: --pick <row numbers of the table>, --interactive (choose rows on the terminal),
#            --xmx 16g (java heap), --jar <BaseX jar>, --overwrite
#
# A folder is one BaseX database (the folder with inf.basex) or a parent folder
# holding several. `list` prints one numbered table of every scenario found;
# `merge` prints the same table for its folders and copies the chosen rows
# (default: all rows). A scenario name may be chosen only once. Document paths
# are kept. The BaseX jar is taken from --jar, then env BASEX_JAR, then the
# rgcam package, then JAR_FALLBACK below. A document is copied in-process
# (db:add) when its database is in the same parent folder as the new database;
# otherwise it is exported to a temporary XML file next to the new database
# and added from there.
################################################################################

JAR_FALLBACK <- "/home/jiheun/gcam/gcam-kaist9-nmsf2/libs/jars/BaseX-9.5.2.jar"
# GCAM writes its databases without indexes; keep the merged one the same
NO_INDEX <- paste0("-Dorg.basex.", c("TEXTINDEX", "ATTRINDEX", "TOKENINDEX"), "=false")

usage <- function() {
  cat("Usage:\n",
      "  Rscript kaist/core/tools/merge_basex_dbs.R list <folder> [<folder> ...]\n",
      "  Rscript kaist/core/tools/merge_basex_dbs.R merge <new db folder> <folder>[:<scenario name>] ...\n",
      "<folder> is a BaseX database folder or a parent folder holding several databases.\n",
      "Options:\n",
      "  --pick 1,3,5   merge only these rows of the scenario table (numbers as printed by list)\n",
      "  --interactive  print the scenario table and choose the rows on the terminal\n",
      "  --xmx <size>   java heap (default 16g)\n",
      "  --jar <path>   BaseX jar (default: $BASEX_JAR, rgcam's jar, or ", JAR_FALLBACK, ")\n",
      "  --overwrite    replace the new database if it exists\n", sep = "")
}

parse_args <- function(args) {
  opt <- list(xmx = "16g", jar = NULL, pick = NULL, interactive = FALSE, overwrite = FALSE,
              pos = character())
  i <- 1
  while (i <= length(args)) {
    a <- args[i]
    if (a %in% c("--xmx", "--jar", "--pick")) {
      if (i == length(args)) stop(a, " needs a value")
      opt[[sub("^--", "", a)]] <- args[i + 1]
      i <- i + 2
    } else if (a %in% c("--overwrite", "--interactive")) {
      opt[[sub("^--", "", a)]] <- TRUE
      i <- i + 1
    } else if (startsWith(a, "--")) {
      stop("unknown option: ", a)
    } else {
      opt$pos <- c(opt$pos, a)
      i <- i + 1
    }
  }
  if (!grepl("^[0-9]+[kKmMgG]?$", opt$xmx)) stop("bad --xmx value: ", opt$xmx)
  if (!is.null(opt$pick) && opt$interactive) stop("use either --pick or --interactive")
  opt
}

find_jar <- function(jar) {
  if (!is.null(jar)) {
    if (!file.exists(jar)) stop("BaseX jar not found: ", jar)
    return(jar)
  }
  rgcam_jars <- list.files(system.file("ModelInterface", "jars", package = "rgcam"),
                           "^BaseX.*\\.jar$", full.names = TRUE)
  cands <- c(Sys.getenv("BASEX_JAR"), rgcam_jars, JAR_FALLBACK)
  cands <- cands[nzchar(cands) & file.exists(cands)]
  if (length(cands) == 0) stop("BaseX jar not found: use --jar or set BASEX_JAR")
  cands[1]
}

# absolute path; the last part may not exist yet (new database)
abs_path <- function(p) {
  p <- sub("/+$", "", p)
  if (dir.exists(p)) return(normalizePath(p))
  file.path(normalizePath(dirname(p), mustWork = FALSE), basename(p))
}

is_db <- function(p) file.exists(file.path(p, "inf.basex"))

# XQuery string literal
xq_str <- function(x) paste0('"', gsub("&", "&amp;", gsub('"', '""', x, fixed = TRUE), fixed = TRUE), '"')

# Run the BaseX command line with DBPATH = parent: one -c per command, then an
# optional XQuery (written to a temp file). Returns the output lines.
basex <- function(parent, commands = character(), query = NULL, out = NULL, props = character()) {
  args <- c(paste0("-Xmx", OPT$xmx), shQuote(paste0("-Dorg.basex.DBPATH=", parent)), props,
            "-cp", shQuote(JAR), "org.basex.BaseX")
  if (!is.null(out)) args <- c(args, "-sindent=no", paste0("-o", shQuote(out)))
  for (cmd in commands) args <- c(args, "-c", shQuote(cmd))
  if (!is.null(query)) {
    qf <- tempfile(fileext = ".xq")
    on.exit(unlink(qf))
    writeLines(query, qf)
    args <- c(args, shQuote(qf))
  }
  res <- suppressWarnings(system2("java", args, stdout = TRUE, stderr = TRUE))
  status <- attr(res, "status")
  if (!is.null(status) && status != 0) {
    stop("java/BaseX failed (exit ", status, "):\n  java ", paste(args, collapse = " "), "\n",
         paste(res, collapse = "\n"))
  }
  res
}

# One row per document: parent, db, doc (document path), name, date
list_scenarios <- function(parent, dbs) {
  query <- sprintf(
    'string-join(
       for $db in (%s)
       for $p in db:list($db)
       let $s := db:open($db, $p)/scenario
       return string-join(($db, $p, string($s[1]/@name), string($s[1]/@date)), "&#9;"),
       "&#10;")', paste(xq_str(dbs), collapse = ", "))
  lines <- basex(parent, query = query)
  lines <- lines[grepl("\t.*\t.*\t", lines)]
  if (length(lines) == 0) {
    return(data.frame(parent = character(), db = character(), doc = character(),
                      name = character(), date = character()))
  }
  d <- read.delim(text = lines, header = FALSE, sep = "\t", quote = "", colClasses = "character",
                  col.names = c("db", "doc", "name", "date"))
  cbind(parent = parent, d)
}

# Every scenario of the "<folder>[:<scenario name>]" arguments, in that order,
# numbered 1..n in column n (the numbers used by --pick and --interactive)
candidates <- function(specs) {
  rows <- lapply(specs, function(spec) {
    path <- spec
    scen <- NULL
    if (!dir.exists(spec) && grepl(":", spec, fixed = TRUE)) {
      path <- sub(":[^:]*$", "", spec)
      scen <- sub("^.*:", "", spec)
    }
    path <- abs_path(path)
    if (!dir.exists(path)) stop("folder not found: ", path)
    if (is_db(path)) {
      d <- list_scenarios(dirname(path), basename(path))
    } else {
      if (!is.null(scen)) stop(":<scenario name> needs a database folder, not a parent folder: ", spec)
      subs <- list.dirs(path, recursive = FALSE)
      subs <- subs[is_db(subs)]
      if (length(subs) == 0) stop("no BaseX database in ", path, " (no inf.basex)")
      d <- list_scenarios(path, basename(subs))
    }
    if (!is.null(scen)) {
      hit <- d[d$name == scen, ]
      if (nrow(hit) == 0) {
        stop("scenario '", scen, "' not found in ", path, "; available: ",
             paste(unique(d$name), collapse = ", "))
      }
      d <- hit
    }
    d
  })
  d <- do.call(rbind, rows)
  cbind(n = seq_len(nrow(d)), d)
}

print_table <- function(d) {
  if (nrow(d) == 0) {
    cat("(no documents)\n")
    return(invisible())
  }
  n <- if (is.null(d[["n"]])) seq_len(nrow(d)) else d[["n"]]
  tab <- list("#" = n, database = file.path(d$parent, d$db), scenario = d$name, date = d$date,
              document = d$doc)
  cols <- lapply(names(tab), function(k) {
    format(c(k, as.character(tab[[k]])), justify = if (k == "#") "right" else "left")
  })
  cat(do.call(paste, c(cols, sep = "  ")), sep = "\n")
}

fmt_secs <- function(s) if (s < 120) sprintf("%.0f s", s) else sprintf("%.1f min", s / 60)

# "1,3,5" -> row numbers
parse_pick <- function(s, n) {
  parts <- trimws(strsplit(s, ",", fixed = TRUE)[[1]])
  parts <- parts[nzchar(parts)]
  if (length(parts) == 0 || !all(grepl("^[0-9]+$", parts))) {
    stop("bad pick '", s, "': use row numbers like 1,3,5")
  }
  idx <- unique(as.integer(parts))
  if (any(idx < 1 | idx > n)) stop("pick out of range (1-", n, "): ", s)
  idx
}

# ask on the terminal which rows to merge
choose_interactive <- function(cand) {
  con <- file("stdin", "r")
  on.exit(close(con))
  ask <- function(prompt) {
    cat(prompt)
    ans <- readLines(con, n = 1)
    if (length(ans) == 0) stop("cancelled (no input)")
    trimws(ans)
  }
  repeat {
    ans <- ask("Rows to merge ('all' or numbers like 1,3,5; empty to cancel): ")
    if (!nzchar(ans)) stop("cancelled")
    idx <- if (ans == "all") cand$n else
      tryCatch(parse_pick(ans, nrow(cand)), error = function(e) {
        cat(conditionMessage(e), "\n")
        NULL
      })
    if (is.null(idx)) next
    cat("\nSelected:\n")
    print_table(cand[idx, ])
    if (ask("Merge these? [y/n]: ") %in% c("y", "Y", "yes")) return(idx)
  }
}

# ---- commands ---------------------------------------------------------------

do_list <- function(specs) print_table(candidates(specs))

do_merge <- function(target, specs) {
  t_start <- Sys.time()
  target <- abs_path(target)
  parent <- dirname(target)
  name <- basename(target)
  if (!dir.exists(parent)) stop("parent folder of the new database not found: ", parent)
  if (grepl("[^A-Za-z0-9_.-]", name)) stop("database name may use letters, digits, '_', '-', '.' only: ", name)
  if (dir.exists(target)) {
    if (!OPT$overwrite) stop("already exists: ", target, " (use --overwrite to replace it)")
    if (!is_db(target)) stop("refusing to overwrite a folder that is not a BaseX database: ", target)
  }

  cand <- candidates(specs)
  if (nrow(cand) == 0) stop("no scenarios found")
  cat("Scenarios found:\n")
  print_table(cand)
  cat("\n")
  idx <- if (OPT$interactive) choose_interactive(cand)
         else if (!is.null(OPT$pick)) parse_pick(OPT$pick, nrow(cand))
         else cand$n
  sel <- cand[idx, ]
  if (any(file.path(sel$parent, sel$db) == target)) {
    stop("the new database cannot be one of the sources: ", target, " (use --pick to leave its rows out)")
  }
  dupn <- unique(sel$name[duplicated(sel$name)])
  if (length(dupn) > 0) {
    cat("A scenario name can be merged only once; pick one row of each (--pick or <folder>:<scenario name>):\n")
    print_table(sel[sel$name %in% dupn, ])
    stop("scenario name selected more than once: ", paste(dupn, collapse = ", "))
  }

  if (dir.exists(target)) unlink(target, recursive = TRUE)
  basex(parent, commands = paste("CREATE DB", name), props = NO_INDEX)
  cat("Created", target, "\n")

  for (i in seq_len(nrow(sel))) {
    t0 <- Sys.time()
    src <- file.path(sel$parent[i], sel$db[i])
    cat(sprintf("Adding %s (%s) from %s ... ", sel$doc[i], sel$name[i], src))
    if (sel$parent[i] == parent) {
      query <- sprintf("db:add(%s, db:open(%s, %s), %s)",
                       xq_str(name), xq_str(sel$db[i]), xq_str(sel$doc[i]), xq_str(sel$doc[i]))
      basex(parent, query = query, props = NO_INDEX)
    } else {
      tmp <- file.path(parent, sprintf("%s_tmp_%d_%s.xml", name, Sys.getpid(), i))
      on.exit(unlink(tmp), add = TRUE)
      basex(sel$parent[i], query = sprintf("db:open(%s, %s)", xq_str(sel$db[i]), xq_str(sel$doc[i])), out = tmp)
      basex(parent, query = sprintf("db:add(%s, %s, %s)", xq_str(name), xq_str(tmp), xq_str(sel$doc[i])),
            props = NO_INDEX)
      unlink(tmp)
    }
    cat(fmt_secs(as.numeric(Sys.time() - t0, units = "secs")), "\n")
  }

  cat("\nScenarios in", target, "\n")
  print_table(list_scenarios(parent, name))
  size_gb <- sum(file.size(list.files(target, full.names = TRUE))) / 1024^3
  cat(sprintf("\nDone: %d document(s), %.1f GB, %s\n", nrow(sel), size_gb,
              fmt_secs(as.numeric(Sys.time() - t_start, units = "secs"))))
}

# ---- main -------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  usage()
  quit(status = 1)
}
tryCatch({
  OPT <- parse_args(args)
  JAR <- find_jar(OPT$jar)
  cmd <- OPT$pos[1]
  rest <- OPT$pos[-1]
  if (cmd == "list" && length(rest) >= 1) {
    do_list(rest)
  } else if (cmd == "merge" && length(rest) >= 2) {
    do_merge(rest[1], rest[-1])
  } else {
    usage()
    quit(status = 1)
  }
}, error = function(e) {
  cat("Error:", conditionMessage(e), "\n", file = stderr())
  quit(status = 1)
})
