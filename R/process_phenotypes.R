# extract strain, isotype dataframe from database
generate_isotype_lookup <- function(species = "ce") {

    if ( species == "ce" ) {
        isotype_lookup <- dplyr::collect(get_db("strain")) %>%
            dplyr::mutate(strain_names = ifelse(!is.na( previous_names ),
                                                paste( strain, previous_names, sep = "|" ),
                                                strain )) %>%
            tidyr::separate_rows(strain_names, sep = "\\|") %>%
            dplyr::select(strain, previous_name = strain_names, isotype) %>%
            dplyr::distinct()
    }

    return( isotype_lookup )
}



#' Resolve strain names to isotypes
#'
#' \code{resolve_isotypes} takes a vector of strain names and converts them to CeNDR-defined isotype names
#'
#' @param strains a vector of strain names to change to isotype names.
#' @return Output is a vector with isotype names
#' @importFrom dplyr %>%
#' @export
resolve_isotypes <- function(...) {

    isotype_lookup = generate_isotype_lookup()
    strains <- unlist(list(...))

    purrr::map_chr(strains, function(x) {
        isotype <- isotype_lookup %>%
            dplyr::filter(
                (x == strain) |
                (x == isotype) |
                (x == previous_name)
            ) %>%
            dplyr::pull(isotype) %>%
            unique()

        if (length(isotype) == 0) {
          message(glue::glue("{x} is not a known strain. Isotype set to NA; Please check CeNDR"))
        } else if (length(isotype) > 1) {
          message(glue::glue("{x} resolves to multiple isotypes. Isotype set to NA; Please check CeNDR"))
        }
        if (length(isotype) != 1) {
            isotype <- NA
        }
        isotype
    })

}


# data = strain, trait, phenotype
BAMF_prune <- function(data, remove_outliers = TRUE ){

    categorize1 <- function(data) {
        with(data,
             ( (sixhs >= 1 & ( (s6h + s5h + s4h ) / numst) <= .05))
             | ( (sixls >= 1 & ( (s6l + s5l + s4l) / numst) <= .05))
        )
    }
    # If the 5 innermost bins are discontinuous by more than a 1 bin gap, the
    # observation is in the fifth bin (between 7 and 10x IQR outside the
    # distribution), and the four outermost bins make up less than 5% of the
    # population, mark the observation an outlier
    categorize2 <- function(data) {
        with(data,
             ( (fivehs >= 1 & ( (s6h + s5h + s4h + s3h) / numst) <= .05))
             | ( (fivels >= 1 & ( (s6l + s5l + s4l + s3l) / numst) <= .05))
        )
    }
    # If the 4 innermost bins are discontinuous by more than a 1 bin gap, the
    # observation is in the fourth bin (between 5 and 7x IQR outside the
    # distribution), and the four outermost bins make up less than 5% of the
    # population, mark the observation an outlier
    categorize3 <- function(data) {
        with(data,
             ( (fourhs >= 1 & (s5h + s4h + s3h + s2h) / numst <= .05))
             | ( (fourls >= 1 & (s5l + s4l + s3l + s2l) / numst <= .05))
        )
    }
    napheno <- data[is.na(data$phenotype), ] %>%
        dplyr::mutate(bamfoutlier1 = NA, bamfoutlier2 = NA, bamfoutlier3 = NA)

    datawithoutliers <- data %>%
        # Filter out all of the wash and/or empty wells
        dplyr::filter(!is.na(strain)) %>%
        # Group by trait, the, calculate the first and third
        # quartiles for each of the traits
        dplyr::group_by(trait) %>%
        dplyr::summarise(iqr = IQR(phenotype, na.rm = TRUE),
                         q1 = quantile(phenotype, probs = .25, na.rm = TRUE),
                         q3 = quantile(phenotype, probs = .75,
                                       na.rm = TRUE)) %>%
        # Add a column for the boundaries of each of the bins
        dplyr::mutate(cut1h = q3 + (iqr * 2),
                      cut1l = q1 - (iqr * 2),
                      cut2h = q3 + (iqr * 3),
                      cut2l = q1 - (iqr * 3),
                      cut3h = q3 + (iqr * 4),
                      cut3l = q1 - (iqr * 4),
                      cut4h = q3 + (iqr * 5),
                      cut4l = q1 - (iqr * 5),
                      cut5l = q1 - (iqr * 7),
                      cut5h = q3 + (iqr * 7),
                      cut6l = q1 - (iqr * 10),
                      cut6h = q3 + (iqr * 10)) %>%
        # Join the bin boundaries back to the original data frame
        dplyr::left_join(data, ., by = c("trait")) %>%
        dplyr::ungroup() %>%
        dplyr::rowwise() %>%
        # Add columns tallying the total number of points in each of the bins
        dplyr::mutate(onehs = ifelse(cut2h > phenotype & phenotype >= cut1h,
                                     1, 0),
                      onels = ifelse(cut2l < phenotype & phenotype <= cut1l,
                                     1, 0),
                      twohs = ifelse(cut3h > phenotype & phenotype >= cut2h,
                                     1, 0),
                      twols = ifelse(cut3l < phenotype & phenotype <= cut2l,
                                     1, 0),
                      threehs = ifelse(cut4h > phenotype & phenotype >= cut3h,
                                       1, 0),
                      threels = ifelse(cut4l < phenotype & phenotype <= cut3l,
                                       1, 0),
                      fourhs = ifelse(cut5h > phenotype &  phenotype >= cut4h,
                                      1, 0),
                      fourls = ifelse(cut5l < phenotype &  phenotype <= cut4l,
                                      1, 0),
                      fivehs = ifelse(cut6h > phenotype & phenotype >= cut5h,
                                      1, 0),
                      fivels = ifelse(cut6l < phenotype & phenotype <= cut5l,
                                      1, 0),
                      sixhs = ifelse(phenotype >= cut6h, 1, 0),
                      sixls = ifelse(phenotype <= cut6l, 1, 0)) %>%
        # Group on condition and trait, then sum the total number of data points
        # in each of the IQR multiple bins
        dplyr::group_by(trait) %>%
        dplyr::mutate(s1h = sum(onehs, na.rm = TRUE),
                      s2h = sum(twohs, na.rm = TRUE),
                      s3h = sum(threehs, na.rm = TRUE),
                      s4h = sum(fourhs, na.rm = TRUE),
                      s5h = sum(fivehs, na.rm = TRUE),
                      s1l = sum(onels, na.rm = TRUE),
                      s2l = sum(twols, na.rm = TRUE),
                      s3l = sum(threels, na.rm = TRUE),
                      s4l = sum(fourls, na.rm = TRUE),
                      s5l = sum(fivels, na.rm = TRUE),
                      s6h = sum(sixhs, na.rm = TRUE),
                      s6l = sum(sixls, na.rm = TRUE)) %>%
        # Group on condition and trait, then check to see if the number of
        # points in each bin is more than 5% of the total number of data points
        dplyr::group_by(trait) %>%
        dplyr::mutate(p1h = ifelse(sum(onehs, na.rm = TRUE) / n() >= .05, 1, 0),
                      p2h = ifelse(sum(twohs, na.rm = TRUE) / n() >= .05, 1, 0),
                      p3h = ifelse(sum(threehs, na.rm = TRUE) / n() >= .05, 1, 0),
                      p4h = ifelse(sum(fourhs, na.rm = TRUE) / n() >= .05 ,1, 0),
                      p5h = ifelse(sum(fivehs, na.rm = TRUE) / n() >= .05 ,1 ,0),
                      p6h = ifelse(sum(sixhs, na.rm = TRUE) / n() >= .05 ,1, 0),
                      p1l = ifelse(sum(onels, na.rm = TRUE) / n() >= .05 ,1, 0),
                      p2l = ifelse(sum(twols, na.rm = TRUE) / n() >= .05 ,1, 0),
                      p3l = ifelse(sum(threels, na.rm = TRUE) / n() >= .05 ,1,0),
                      p4l = ifelse(sum(fourls, na.rm = TRUE) / n() >= .05 , 1, 0),
                      p5l = ifelse(sum(fivels, na.rm = TRUE) / n() >= .05, 1, 0),
                      p6l = ifelse(sum(sixls,
                                       na.rm = TRUE) / n() >= .05, 1, 0)) %>%
        # Count the number of observations in each condition/trait combination
        dplyr::mutate(numst = n()) %>%
        # Group on trait, then filter out NAs in any of the added
        # columns
        dplyr::group_by(trait) %>%
        dplyr::filter(!is.na(trait), !is.na(phenotype), !is.na(iqr), !is.na(q1),
                      !is.na(q3), !is.na(cut1h), !is.na(cut1l), !is.na(cut2h),
                      !is.na(cut2l), !is.na(cut3h), !is.na(cut3l),
                      !is.na(cut4h), !is.na(cut4l), !is.na(cut5l),
                      !is.na(cut5h), !is.na(cut6l), !is.na(cut6h),
                      !is.na(onehs), !is.na(onels), !is.na(twohs),
                      !is.na(twols), !is.na(threehs), !is.na(threels),
                      !is.na(fourhs), !is.na(fourls), !is.na(fivehs),
                      !is.na(fivels), !is.na(sixhs), !is.na(sixls),
                      !is.na(s1h), !is.na(s2h), !is.na(s3h), !is.na(s4h),
                      !is.na(s5h), !is.na(s1l), !is.na(s2l), !is.na(s3l),
                      !is.na(s4l), !is.na(s5l), !is.na(s6h), !is.na(s6l),
                      !is.na(p1h), !is.na(p2h), !is.na(p3h), !is.na(p4h),
                      !is.na(p5h), !is.na(p6h), !is.na(p1l), !is.na(p2l),
                      !is.na(p3l), !is.na(p4l), !is.na(p5l), !is.na(p6l),
                      !is.na(numst)) %>%
        # Add three columns stating whether the observation is an outlier
        # based the three outlier detection functions below
        dplyr::ungroup() %>%
        dplyr::mutate(cuts = categorize1(.),
                      cuts1 = categorize2(.),
                      cuts2 = categorize3(.))

    if ( remove_outliers == T){
        outliers_removed <- datawithoutliers %>%
            dplyr::rename(bamfoutlier1 = cuts,
                          bamfoutlier2 = cuts1,
                          bamfoutlier3 = cuts2) %>%
            dplyr::filter(!bamfoutlier1 & !bamfoutlier2 & !bamfoutlier3) %>%
            dplyr::select(trait, strain, phenotype)

        return(outliers_removed)
    } else {
        with_outliers <- datawithoutliers %>%
            dplyr::rename(bamfoutlier1 = cuts,
                          bamfoutlier2 = cuts1,
                          bamfoutlier3 = cuts2) %>%
            dplyr::select(trait, strain, phenotype, bamfoutlier1, bamfoutlier2, bamfoutlier3) %>%
            dplyr::mutate(outlier = ifelse( bamfoutlier1 | bamfoutlier2 | bamfoutlier3, TRUE, FALSE)) %>%
            dplyr::select(strain, trait, phenotype, outlier)

        return(with_outliers)
    }
}

#' Process phenotypes for mapping
#'
#' \code{process_phenotypes} takes input raw phenotype data and converts strain names to
#' isotype names, summarizes replicate data, and eliminates outliers.
#'
#' @param df a dataframe with a strain column and columns for each trait for processing.
#' @param summarize_replicates summarization method, currently limited to "mean" or "median"
#' @param prune_method method for eliminating outliers, currently limited to "BAMF", "Z", "TUKEY", "MAD"
#' @param remove_outliers boolean to specify if outliers should be eliminated within the function.
#' If FALSE, additional columns will be output specifying if the strain phenotype is an outier.
#' @param threshold integer value defining the threshold for outlier removal, default = 2
#' @return Output is a dataframe with
#' @export
process_phenotypes <- function(df,
                               summarize_replicates = "mean",
                               prune_method = "BAMF",
                               remove_outliers = TRUE,
                               threshold = 2){

    if ( sum(grepl(colnames(df)[1], "Strain", ignore.case = T)) == 0 ) {
        message(glue::glue("Check input data format, strain should be the first column."))
    }

    # ~ ~ ~ # resolve strain isotypes # ~ ~ ~ #
    # get strain isotypes
    strain_isotypes_db <- generate_isotype_lookup()
    # identify strains that were phenotyped, but are not part of an isotype
    non_isotype_strains <- dplyr::filter(df,
                                         !(strain %in% strain_isotypes_db$strain),
                                         !(strain %in% strain_isotypes_db$isotype))
    # remove any strains identified to not fall into an isotype
    if ( nrow(non_isotype_strains) > 0 ) {

        strains_to_remove <- unique(non_isotype_strains$strain)

        message(glue::glue("Removing strain(s) {strains_to_remove} because they do not fall into a defined isotype."))

        df_non_isotypes_removed <- dplyr::filter( df, !( strain %in% strains_to_remove) )
    } else {
        df_non_isotypes_removed <- df
    }

    # ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ # Resolve Isotypes # ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ #
    df_isotypes_resolved <- df_non_isotypes_removed %>%
        dplyr::group_by(strain) %>%
        dplyr::mutate(isotype = resolve_isotypes(strain)) %>%
        dplyr::ungroup() %>%
        tidyr::gather(trait, phenotype, -strain, -isotype) %>%
        dplyr::filter(!is.na(phenotype))

    # ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ # Summarize Replicate Data # ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ #
    df_replicates_summarized <- df_isotypes_resolved %>%
        dplyr::group_by(isotype, trait) %>% {
            if (summarize_replicates == "mean") dplyr::summarise(., phenotype = mean( phenotype, na.rm = T ) )
            else if (summarize_replicates == "median") dplyr::summarise(., phenotype = median( phenotype, na.rm = T ) )
            else  message(glue::glue("Please choose mean or median as options for summarizeing replicate data.")) } %>%
        dplyr::rename(strain = isotype) %>%
        dplyr::ungroup()

    # ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ # Outlier Functions # ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ #
    is_out_tukey <- function(x, k = threshold, na.rm = TRUE) {
        quar <- quantile(x, probs = c(0.25, 0.75), na.rm = na.rm)
        iqr <- diff(quar)

        ( !(quar[1] - k * iqr <= x) ) | ( !(x <= quar[2] + k * iqr) )
    }
    is_out_z <- function(x, thres = threshold, na.rm = TRUE) {
        ( !abs(x - mean(x, na.rm = na.rm)) <= thres * sd(x, na.rm = na.rm) )
    }
    is_out_mad <- function(x, thres = threshold, na.rm = TRUE) {
        ( !abs(x - median(x, na.rm = na.rm)) <= thres * mad(x, na.rm = na.rm) )
    }

    # ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ # Perform outlier removal # ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ ## ~ ~ ~ #
    if ( prune_method == "BAMF" ) {
        df_outliers <- BAMF_prune(df_replicates_summarized, remove_outliers = FALSE)
    } else {
        df_outliers <-  dplyr::ungroup(df_replicates_summarized) %>%
            dplyr::group_by(trait) %>% {
                if (prune_method == "MAD") dplyr::transmute_if(., is.numeric, dplyr::funs( outlier = is_out_mad ) )
                else if (prune_method == "TUKEY") dplyr::transmute_if(., is.numeric, dplyr::funs( outlier = is_out_tukey ) )
                else if (prune_method == "Z") dplyr::transmute_if(., is.numeric, dplyr::funs( outlier = is_out_z ) )
                else  message(glue::glue("Please choose BAMF, MAD, TUKEY, or Z as options for summarizeing replicate data.")) } %>%
            dplyr::ungroup() %>%
            dplyr::bind_cols(., dplyr::ungroup(df_replicates_summarized)) %>%
            dplyr::select(strain, trait, phenotype, outlier)
    }

    if (remove_outliers == TRUE ) {
        processed_phenotypes_output <- df_outliers %>%
            dplyr::filter( !outlier ) %>%
            dplyr::select( -outlier ) %>%
            tidyr::spread( trait, phenotype)
    } else {
        processed_phenotypes_output <- df_outliers %>%
            tidyr::spread( trait, phenotype)
    }

    return(processed_phenotypes_output)
}

