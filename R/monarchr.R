# monarchr.R
#
# This is an interface into the monarch_initiative web services api.
#
# It was written by charlieccarey @ somepopular email service.
#
# For example, get a table of homolog information from
# monarch_initiative.org
#
#     gene <- bioentity_homologs("NCBIGene:8314")
#     homologs <- bioentity_homologs(gene)

# TODO: Find out what all the tags are for each of these types.
EVID_TAGS = c("evidence", "traceable author statement", "asserted information")
# DISEASE_TAGS = c("MONDO:")
PUBS_TAGS = c("PMID:", "-PUB-") # "ZFIN:ZDB-PUB-030905-1"


# TODO(?): handle more than 100 rows of results. We need to know whether the API pages beyond some number of results or size of results.
# TODO: Add setting query parameter values on each method. for example, 100 row limit is insufficient for interactions.
# TODO: When object.taxon is empty, remove column.
# TODO: Remove any empty columns in tibbles.

# -----------------------------------------------------------------------------
#
#
#                     MAKING BIOENTITY REQUESTS
#
#
# -----------------------------------------------------------------------------


#' Gets response from monarch API.
#'
#' If a server status error is encoutered, content is set to NULL.
#' Otherwise it is parsed from json to R objects.
#'
#' @param url URL as a string.
#'
#' @return A monarch_api S3 class with content as R objects, the url
#' used for the query and the server response.
#' @export
#'
#' @examples
#' url <- "https://api.monarchinitiative.org/api/bioentity/gene/NCBIGene%3A8314?rows=100"
#' resp <- monarch_api(url)
monarch_api <- function(url) {
  url <- paste0(url, "&format=json")
  result <- NULL
  resp <- httr::GET(url)
  if (httr::status_code(resp) != 200) {
    message(paste("Something went wrong with GET query:", url))
    message(paste("Status code:", httr::status_code(resp)))
  }
  if (httr::http_type(resp) != "application/json") {
    warning("API did not return json", call. = FALSE)
  }
  else {
    result <- jsonlite::fromJSON(httr::content(resp, as = 'text', encoding = 'UTF-8'))
  }

  structure(
    list(
      content = result,
      url = url,
      response = resp
    ),
    class = "monarch_api"
  )
}

# -----------------------------------------------------------------------------
#
#
#           Content extraction common to all(?) Bioentity content.
#
#
# -----------------------------------------------------------------------------

#' Extracts simplified content from response.
#'
#' @param df a data.frame obtained by flattening the json response's content.
#'
#' @return a tibble with just the core information of interest.
#' @export
#'
#' @examples
#' gene <-"NCBIGene:8314"
#' gene <- utils::URLencode(gene, reserved = TRUE)
#' query <- list(rows=100, fetch_objects="true")
#' url <- build_monarch_url(path = list("/api/bioentity/gene",
#'                                      gene,
#'                                      "diseases/"),
#'                          query = query)
#' resp <- monarch_api(url)
#' resp <- jsonlite::flatten(resp$content$associations,
#'                           recursive=TRUE)
#' extract_be_content(resp)
extract_be_content <- function(df) {
  #   debugging:
  #     df <- as_tibble(df[, !apply(is.na(df), 2, all)]) # deselect columns w/ no info
  #     str(df, max.level = 1) # OR
  #     as_tibble(df).

  # Accessing in a legit manner via the evidence_graph.nodes.
  # (As opposed to extract_matching_phrases_from_lists())
  #
  # d_terms <- lapply(df$evidence_graph.nodes, function(x) { # each data.frame 'id', 'lbl'
  #   x[which(grepl(paste(DISEASE_TAGS, collapse = "|"), x$id)),]
  # })
  # d_terms <- dplyr::bind_rows(d_terms)

  evids <- extract_matching_phrases_from_lists(df$evidence_graph.nodes, EVID_TAGS)
  pubs <- extract_matching_phrases_from_lists(df$publications, PUBS_TAGS)
  sources <- list_of_paths_to_basenames(df$provided_by)

  df <- df[c("subject.taxon.label",
             "subject.id",
             "subject.label",
             "relation.label",
             "object.label",
             "object.id",
             "object.taxon.label")]

  df <- do.call('cbind.data.frame',
                list(df,
                     evidence = evids,
                     publications = pubs,
                     provided_by = sources))
  names(df) <- sub('.label', '', names(df))

  return(tibble::as_tibble(df))
}


# -----------------------------------------------------------------------------
#
#
#                   EACH IMPLEMENTED BIOENTITY REQUESTS AND RESULTS
#                   (not all Bioentity APIs are (fully?) functional)
#
#
# -----------------------------------------------------------------------------


#' Gets homolog associations for a gene.
#'
#' e.g. Given a gene ID, finds homologs for that gene and lists their associations
#'
#' The monarch_api class is included in return mainly for debugging the REST requests.
#'
#' https://api.monarchinitiative.org/api/bioentity/gene/NCBIGene%3A8314?rows=100&fetch_objects=true
#'
#' @param gene A valid monarch initiative gene id.
#'
#' @return A list of (tibble of homolog information, monarch_api S3 class).
#' @export
#'
#' @examples
#' gene <-"NCBIGene:8314"
#' bioentity_gene_homology_associations(gene)
bioentity_gene_homology_associations <- function(gene) { # TODO: definitely want to add response taxons.
  # TODO: Needs extensive testing with various NCBIGene and other IDs.
  # TODO: Synonyms, phenotpye_assoc, disease_assoc, genotype_assoc are also populated.
  # TODO:   do we want to process them all at once and access them individually?
  # TODO: Need a better idea of what this monarch is trying to uncover here,
  # TODO:   and where it comes from vs. other homolog, phenotype, genotype etc. methods.
  gene <- utils::URLencode(gene, reserved = TRUE)

  query <- list(rows=100, fetch_objects="true")
  url <- build_monarch_url(path = list("/api/bioentity/gene", gene),
                           query = query)

  resp <- monarch_api(url)
  homs <- jsonlite::flatten(resp$content$homology_associations, recursive=TRUE)

  tb <- extract_be_content(homs)

  return(list(homologs = tb,
              response = resp))
}

#' Gets homologs for a gene.
#'
#' Replicates info in view: https://api.monarchinitiative.org/api/#!/bioentity/get_gene_homologs
#'
#' The monarch_api class is included in return mainly for debugging.
#'
#' https://api.monarchinitiative.org/api/bioentity/gene/NCBIGene%3A8314/homologs/?rows=100&fetch_objects=true
#'
#'
#' @param gene A valid monarch initiative gene id.
#'
#' @return A list of (tibble of homolog information, monarch_api S3 class).
#' @export
#'
#' @examples
#' gene <-"NCBIGene:8314"
#' bioentity_homologs(gene)
bioentity_homologs <- function(gene) {
  # TODO: Needs extensive testing with various NCBIGene and other IDs.
  gene <- utils::URLencode(gene,
                           reserved = TRUE)

  query <- list(rows=100, fetch_objects="true")
  url <- build_monarch_url(path = list("/api/bioentity/gene",
                                       gene, "homologs/"),
                           query = query)
  resp <- monarch_api(url)
  homs <- jsonlite::flatten(resp$content$associations,
                            recursive=TRUE)

  tb <- extract_be_content(homs)

  return( list(homologs = tb,
               response = resp) )
}


#' Gets diseases associated with a gene.
#'
#' Given a gene, what diseases are associated with it.
#'
#' https://api.monarchinitiative.org/api/bioentity/gene/NCBIGene%3A8314/diseases/?rows=100&fetch_objects=true&format=json
#'
#' @param gene A valid monarch initiative gene id.
#'
#' @return A list of (tibble of disease information, monarch_api S3 class).
#' @export
#'
#' @examples
#' gene <- "NCBIGene:8314"
#' bioentity_diseases_assoc_w_gene(gene)
bioentity_diseases_assoc_w_gene <- function(gene) {
  gene <- utils::URLencode(gene, reserved = TRUE)
  query <- list(rows=100, fetch_objects="true")
  url <- build_monarch_url(path = list("/api/bioentity/gene",
                                       gene, "diseases/"),
                           query = query)
  resp <- monarch_api(url)

  dis <- jsonlite::flatten(resp$content$associations,
                           recursive=TRUE)

  tb <- extract_be_content(dis)

  return( list(diseases = tb,
               response = resp) )
}


#' Gets phenotypes associated with a gene.
#'
#' Given a gene, what phenotypes are associated with it.
#'
#' https://api.monarchinitiative.org/api/bioentity/gene/NCBIGene%3A8314/phenotypes/?rows=100&fetch_objects=true
#'
#' @param gene A valid monarch initiative gene id.
#'
#' @return A list of (tibble of phenotype information, monarch_api S3 class).
#' @export
#'
#' @examples
#' gene <- "NCBIGene:8314"
#' bioentity_phenotypes_assoc_w_gene(gene)
bioentity_phenotypes_assoc_w_gene <- function(gene) {
  gene <- utils::URLencode(gene, reserved = TRUE)
  query <- list(rows=100, fetch_objects="true")
  url <- build_monarch_url(path = list("/api/bioentity/gene",
                                       gene, "phenotypes/"),
                           query = query)
  resp <- monarch_api(url)

  phe <- jsonlite::flatten(resp$content$associations,
                           recursive=TRUE)

  tb <- extract_be_content(phe)

  return( list(phenotypes = tb,
               response = resp) )
}


#' Gets expression anatomy associated with a gene.
#'
#' Given a gene, what expression anatomy is associated with it.
#'
#' https://api.monarchinitiative.org/api/bioentity/gene/NCBIGene%3A8314/expression/anatomy?rows=100&fetch_objects=true
#'
#' @param gene A valid monarch initiative gene id.
#'
#' @return A list of (tibble of anatomy information, monarch_api S3 class).
#' @export
#'
#' @examples
#' gene <- "NCBIGene:8314"
#' bioentity_exp_anatomy_assoc_w_gene(gene)
bioentity_exp_anatomy_assoc_w_gene <- function(gene) {
  gene <- utils::URLencode(gene, reserved = TRUE)
  query <- list(rows=100, fetch_objects="true")
  url <- build_monarch_url(path = list("/api/bioentity/gene",
                                       gene, "expression/anatomy"), # Note, slightly different request form.
                           query = query)
  resp <- monarch_api(url)

  anat <- jsonlite::flatten(resp$content$associations,
                            recursive=TRUE)

  tb <- extract_be_content(anat)

  return( list(anatomy = tb,
               response = resp) )
}

# TODO: wait for a cleaner endpoint in the biolinks API.
# #' Gets variants associated with a gene.
# #'
# #' Given a gene, what variants are associated with it.
# #'
# #' https://api.monarchinitiative.org/api/bioentity/gene/NCBIGene%3A8314/phenotypes/?rows=100&fetch_objects=true
# #'
# #' @param gene A valid monarch initiative gene id.
# #'
# #' @return A list of (tibble of variant information, monarch_api S3 class).
# #' @export
# #'
# #' @examples
# #' gene <- "NCBIGene:8314"
# #' bioentity_variants_assoc_w_gene(gene)
# # bioentity_variants_assoc_w_gene <- function(gene) {
#   gene <- utils::URLencode(gene, reserved = TRUE)
#   query <- list(rows=100, fetch_objects="true")
#   url <- build_monarch_url(path = list("/api/bioentity/gene",
#                                        gene, "variants/"),
#                            query = query)
#   resp <- monarch_api(url)
#
#   variants <- jsonlite::flatten(resp$content$associations,
#                            recursive=TRUE)
#
#   tb <- extract_be_content(variants)
#
#   return( list(variants = tb,
#                response = resp) )
# }

#' Gets interactions associated with a gene.
#'
#' Given a gene, what variants are associated with it.
#'
#' https://api.monarchinitiative.org/api/bioentity/gene/HGNC%3A950/interactions/?rows=100&fetch_objects=true
#'
#' @param gene A valid monarch initiative gene id.
#'
#' @return A list of (tibble of variant information, monarch_api S3 class).
#' @export
#'
#' @examples
#' gene <- "NCBIGene:8314"
#' bioentity_interactions_assoc_w_gene(gene)
bioentity_interactions_assoc_w_gene <- function(gene) {
  gene <- utils::URLencode(gene, reserved = TRUE)
  query <- list(rows=100, fetch_objects="true")
  url <- build_monarch_url(path = list("/api/bioentity/gene",
                                       gene, "interactions/"),
                           query = query)
  resp <- monarch_api(url)

  intxns <- jsonlite::flatten(resp$content$associations,
                                recursive=TRUE)

  tb <- extract_be_content(intxns)

  return( list(interactions = tb,
               response = resp) )
}


#' Gets pathways associated with a gene.
#'
#' Given a gene, what pathways are associated with it.
#'
#'  https://api.monarchinitiative.org/api/bioentity/gene/HGNC%3A950/pathways/?rows=100&fetch_objects=true
#'
#'
#' @param gene A valid monarch initiative gene id.
#'
#' @return A list of (tibble of variant information, monarch_api S3 class).
#' @export
#'
#' @examples
#' gene <- "NCBIGene:8314"
#' bioentity_pathways_assoc_w_gene(gene)
bioentity_pathways_assoc_w_gene <- function(gene) {
  gene <- utils::URLencode(gene, reserved = TRUE)
  query <- list(rows=100, fetch_objects="true")
  url <- build_monarch_url(path = list("/api/bioentity/gene",
                                       gene, "pathways/"),
                           query = query)
  resp <- monarch_api(url)

  pths <- jsonlite::flatten(resp$content$associations,
                              recursive=TRUE)

  tb <- extract_be_content(pths)

  return( list(pathways = tb,
               response = resp) )
}


# -----------------------------------------------------------------------------
#
#
#                   UNIMPLEMENTED BIOENTITY REQUESTS AND RESULTS
#                   (not all Bioentity APIs are (fully?) functional)
#
#
# -----------------------------------------------------------------------------


# no skeleton code yet.
