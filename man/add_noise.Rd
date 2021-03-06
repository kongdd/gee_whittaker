% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/simu_noise.R
\name{add_noise}
\alias{add_noise}
\title{add_noise}
\usage{
add_noise(y, perc = 0.1, seed, I)
}
\arguments{
\item{I}{If provide, noise position is fixed at \code{I}.}
}
\description{
QC variable also returned.
Same as MOD13A1 SummaryQA, 0: good value, 3: cloud contaminated.
}
\details{
For each site, repeat 100 times.
}
