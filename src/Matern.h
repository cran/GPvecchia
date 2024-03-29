#define ARMA_WARN_LEVEL 0

#include <iostream>
#include <RcppArmadillo.h>
#include <Rcpp.h>
#include <boost/math/special_functions/bessel.hpp>
#include <boost/math/special_functions/gamma.hpp>

using namespace Rcpp;
using namespace arma;
using namespace std;



mat MaternFun( mat distmat, vec covparms );
