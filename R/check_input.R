# .normalize and .backnormalize function referenced by phenopix package
.normalize     <- function(x, sf) (x-sf[1])/(sf[2]-sf[1])
.backnormalize <- function(x, sf) (x+sf[1]/(sf[2]-sf[1]))*(sf[2]-sf[1])

#' check_input
#'
#' Check input data, interpolate NA values in y, remove spike values, and set
#' weights for NA in y and w.
#'
#' @param t Numeric vector, `Date` variable
#' @param y Numeric vector, vegetation index time-series
#' @param w (optional) Numeric vector, weights of `y`. If not specified,
#' weights of all `NA` values will be `wmin`, the others will be 1.0.
#' @param QC_flag Factor (optional) returned by `qcFUN`, levels should be
#' in the range of `c("snow", "cloud", "shadow", "aerosol", "marginal",
#' "good")`, others will be categoried into `others`. `QC_flag` is
#' used for visualization in [get_pheno()] and [plot_phenofit()].
#' @param nptperyear Integer, number of images per year.
#' @param south Boolean. In south hemisphere, growing year is 1 July to the
#' following year 31 June; In north hemisphere, growing year is 1 Jan to 31 Dec.
#' @param Tn Numeric vector, night temperature, default is null. If provided,
#' Tn is used to help divide ungrowing period, and then get background value in
#' ungrowing season (see details in [phenofit::backval()]).
#' @param perc_wc critical percentage of good- and marginal- quality points for
#' `wc`.
#' @param wmin Double, minimum weight of bad points, which could be smaller
#' the weight of snow, ice and cloud.
#' @param missval Double, which is used to replace NA values in y. If missing,
#' the default vlaue is `ylu[1]`.
#' @param ymin If specified, `ylu[1]` is constrained greater than ymin. This
#' value is critical for bare, snow/ice land, where vegetation amplitude is quite
#' small. Generally, you can set ymin=0.08 for NDVI, ymin=0.05 for EVI,
#' ymin=0.5 gC m-2 s-1 for GPP.
#' @param maxgap Integer, nptperyear/4 will be a suitable value. If continuous
#' missing value numbers less than maxgap, then interpolate those NA values by
#' zoo::na.approx; If false, then replace those NA values with a constant value
#' `ylu[1]`. \cr
#' Replacing NA values with a constant missing value (e.g. background value ymin)
#' is inappropriate for middle growing season points. Interpolating all values
#' by na.approx, it is unsuitable for large number continous missing segments,
#' e.g. in the start or end of growing season.
#' @param alpha Double value in `[0,1]`, quantile prob of ylu_min.
#' @param ... Others will be ignored.
#'
#' @return A list object returned
#' \itemize{
#' \item{t } Numeric vector
#' \item{y0} Numeric vector, original vegetation time-series.
#' \item{y } Numeric vector, checked vegetation time-series, `NA` values
#' are interpolated.
#' \item{w } Numeric vector
#' \item{Tn} Numeric vector
#' \item{ylu} = `[ymin, ymax]`. `w_critical` is used to filter not too bad values.
#'
#' If the percentage good values (w=1) is greater than 30\%, then `w_critical`=1.
#'
#' The else, if the percentage of w >= 0.5 points is greater than 10\%, then
#' `w_critical`=0.5. In boreal regions, even if the percentage of w >= 0.5
#' points is only 10\%, we still can't set `w_critical=wmin`.
#'
#' We can't rely on points with the wmin weights. Then,  \cr
#' `y_good = y[w >= w_critical ]`,  \cr
#' `ymin = pmax( quantile(y_good, alpha/2), 0)`  \cr `ymax = max(y_good)`.
#' }
#'
#' @importFrom zoo na.approx na.approx.default
#' @export
check_input <- function(t, y, w, QC_flag,
    nptperyear, south = FALSE, Tn = NULL,
    perc_wc = 0.4,
    wmin = 0.2,
    ymin, missval,
    maxgap, alpha = 0.02, ...)
{
    if (missing(QC_flag)) QC_flag <- NULL
    if (missing(nptperyear)){
        nptperyear <- ceiling(365/as.numeric(difftime(t[2], t[1], units = "days")))
    }
    if (missing(maxgap)) maxgap = ceiling(nptperyear/12*1.5)

    y0  <- y
    n   <- length(y)
    if (missing(w) || is.null(w)) w <- rep(1, n)

    # ylu   <- quantile(y[w == 1], c(alpha/2, 1 - alpha), na.rm = TRUE) #only consider good value
    # ylu   <- range(y, na.rm = TRUE)
    # only remove low values
    w_critical <- wmin
    if (sum(w == 1, na.rm = TRUE) >= n*perc_wc){
        w_critical <- 1
    }else if (sum(w >= 0.5, na.rm = TRUE) > n*perc_wc){
        # Just set a small portion for boreal regions. In this way, it will give
        # more weights to marginal data.
        w_critical <- 0.5
    }
    y_good <- y[w >= w_critical] %>% rm_empty()
    ylu    <- c(pmax( quantile(y_good, alpha/2), 0),
               quantile(y_good, 1 - alpha/2))

    if (!missing(ymin) && !is.na(ymin)){
        # constrain back ground value
        ylu[1] <- pmax(ylu[1], ymin)
    }
    # When check_ylu, ylu_max is not used. ylu_max is only used for dividing
    # growing seasons.

    # adjust weights according to ylu
    # if (trim){
    #     I_trim    <- y < ylu[1] #| y > ylu[2]
    #     w[I_trim] <- wmin
    # }
    # NAN values check
    if (missing(missval))
        missval <- ylu[1] #- diff(ylu)/10

    # generally, w == 0 mainly occur in winter. So it's seasonable to be assigned as minval
    ## 20180717 error fixed: y[w <= wmin]  <- missval # na is much appropriate, na.approx will replace it.
    # values out of range are setted to wmin weight.
    w[y < ylu[1] | y > max(y_good)] <- wmin # | y > ylu[2],
    # #based on out test marginal extreme value also often occur in winter
    # #This step is really dangerous! (checked at US-Me2)
    y[y < ylu[1]]                  <- missval
    y[y > ylu[2] & w < w_critical] <- missval

    ## 2. rm spike values
    std   <- sd(y, na.rm = TRUE)
    ymean <- movmean(y, 2, SG_style = FALSE) # movmean
    # y[abs(y - ymean) > std]
    # which(abs(y - ymean) > std)
    I_spike <- which(abs(y - ymean) > 2*std & w < w_critical) # 95.44% interval
    y[I_spike] <- NA #missval

    ## 3. gap-fill NA values
    w[is.na(w) | is.na(y)] <- wmin
    w[w <= wmin] <- wmin
    # left missing values were interpolated by `na.approx`
    y <- na.approx.default(y, maxgap = maxgap, na.rm = FALSE)
    # If still have na values after na.approx, just replace it with `missval`.
    y[is.na(y)] <- missval

    if (!is_empty(Tn)){
        Tn <- na.approx.default(Tn, maxgap = maxgap, na.rm = FALSE)
    }
    list(t = t, y0 = y0, y = y, w = w, QC_flag = QC_flag, Tn = Tn, ylu = ylu,
        nptperyear = nptperyear, south = south)
}

#' @importFrom matrixStats rowQuantiles
quantile2 <- function(x, probs = seq(from = 0, to = 1, by = 0.25), na.rm = FALSE){
    dim(x) <- c(1, length(x))
    rowQuantiles(x, probs = probs, na.rm = na.rm)
}

#' check_ylu
#'
#' Curve fitting values are constrained in the range of `ylu`.
#' Only constrain trough value for a stable background value. But not for peak
#' value.
#'
#' @param yfit Numeric vector, curve fitting result
#' @param ylu limits of y value, `[ymin, ymax]`
#'
#' @return yfit, the numeric vector in the range of `ylu`.
#'
#' @export
#' @examples
#' check_ylu(1:10, c(2, 8))
check_ylu <- function(yfit, ylu){
    # I_max <- yfit > ylu[2]
    I_min <- yfit < ylu[1]
    # yfit[I_max] <- ylu[2]
    yfit[I_min] <- ylu[1]
    return(yfit)
}

# #' check_ylu2
# #'
# #' values out of ylu, set to be na and interpolate it.
# #' @export
# check_ylu2 <- function(y, ylu){
#     I <- which(y < ylu[1] | y > ylu[2])
#     if (length(I) > 0){
#         n    <-length(y)
#         y[I] <- NA
#         y <- na.approx(y, na.rm = F)
#         # if still have na values in y
#         I_nona <- which(!is.na(y)) # not NA id
#         if (length(I_nona) != n){
#             # na values must are in tail or head now
#             iBegin <- first(I_nona)
#             iEnd   <- last(I_nona)
#             if (iBegin > 2) y[1:iBegin] <- y[iBegin]
#             if (iEnd < n)   y[iEnd:n]   <- y[iEnd]
#         }
#     }
#     return(y)
# }
