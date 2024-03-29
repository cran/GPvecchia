#' estimate mean and covariance parameters of a Matern covariance function using Vecchia
#'
#' @param data data vector of length n
#' @param locs n x d matrix of spatial locations
#' @param X n x p matrix of trend covariates. default is vector of ones (constant trend).
#'      set to NULL if data are already detrended
#' @param m number of neighbors for vecchia approximation. default is 20
#' @param covmodel covariance model. default is Matern.
#'    see \code{\link{vecchia_likelihood}} for details.
#' @param theta.ini initial values of covariance parameters. nugget variance must be last.
#' @param output.level passed on to trace in the \code{stats::optim} function
#' @param reltol tolerance for the optimization function; by default set to the sqrt of machine
#'      precision
#' @param ... additional input parameters for \code{\link{vecchia_specify}}
#'
#' @return object containing detrended data z, trend coefficients beta.hat,
#'    covariance parameters theta.hat, and other quantities necessary for prediction
#' @examples
#' \donttest{
#' n=10^2; locs=cbind(runif(n),runif(n))
#' covparms=c(1,.1,.5); nuggets=rep(.1,n)
#' Sigma=exp(-fields::rdist(locs)/covparms[2])+diag(nuggets)
#' z=as.numeric(t(chol(Sigma))%*%rnorm(n));
#' data=z+1
#' vecchia.est=vecchia_estimate(data,locs,theta.ini=c(covparms,nuggets[1]))
#' }
#' @export
vecchia_estimate=function(data,locs,X,m=20,covmodel='matern',theta.ini,output.level=1,
                          reltol=sqrt(.Machine$double.eps), ...) {

    ## default trend is constant over space (intercept)
    if(missing(X)){

        beta.hat=mean(data)
        z=data-beta.hat
        trend='constant'

    } else if(is.null(X)){
        ## if X=NULL, do not estimate any trend
        
        beta.hat=c()
        z=data
        trend='none'
        
    } else {
        ## otherwise, estimate and de-trend

        beta.hat=Matrix::solve(crossprod(X),crossprod(X,data))
        z=data-X%*%beta.hat
        trend='userspecified'

    }

    ## specify vecchia approximation
    vecchia.approx=vecchia_specify(locs,m,...)

    ## initial covariance parameter values

    if(all(is.character(covmodel)) && covmodel=='matern'){
        if (missing(theta.ini) || any(is.na(theta.ini))){

            var.res=stats::var(z)
            n=length(z)
            dists.sample=fields::rdist(locs[sample(1:n,min(n,300)),])
            theta.ini=c(.9*var.res,mean(dists.sample)/4,.8,.1*var.res) # var,range,smooth,nugget
        } 
   }

    ## specify vecchia loglikelihood
    n.par=length(theta.ini)
    
    negloglik.vecchia=function(lgparms){
        if(exp(lgparms[3])>10 && all(is.character(covmodel)) && covmodel=='matern'){
            stop("The default optimization routine to find parameters did not converge. Try writing your own optimization.")
        }
        l = -vecchia_likelihood(z,vecchia.approx,exp(lgparms)[-n.par],exp(lgparms)[n.par],covmodel=covmodel)
        return(l)
    }
    

    ## find MLE of theta (given beta.hat)
    #print(negloglik.vecchia(log(theta.ini)))
    non1pars = which(theta.ini != 1)
    parscale = rep(1, length(n.par))
    parscale[non1pars] = log(theta.ini[non1pars])

    opt.result=stats::optim(par=log(theta.ini),
                            fn=negloglik.vecchia,
                            method = "Nelder-Mead",
                            control=list(
                                trace=100,maxit=300, parscale=parscale,
                                reltol=reltol
                          )) # trace=1 outputs iteration counts
    
    theta.hat=exp(opt.result$par)
    names(theta.hat) = c("variance", "range", "smoothness", "nugget")

    ## return estimated parameters
    if(output.level>0){  
        cat('estimated trend coefficients:\n'); print(beta.hat)
        cat('estimated covariance parameters:\n'); print(theta.hat)
    }
    return(list(z=z,beta.hat=beta.hat,theta.hat=theta.hat,
                trend=trend,locs=locs,covmodel=covmodel))

}



#' make spatial predictions using Vecchia based on estimated parameters
#'
#' @param vecchia.est object returned by \code{\link{vecchia_estimate}}
#' @param locs.pred n.p x d matrix of prediction locations
#' @param X.pred n.p x p matrix of trend covariates at prediction locations.
#'      does not need to be specified if constant or no trend was used in
#'      \code{\link{vecchia_estimate}}
#' @param m number of neighbors for vecchia approximation. default is 30.
#' @param ... additional input parameters for \code{\link{vecchia_specify}}
#'
#' @return object containing prediction means mean.pred and variances var.pred
#' @examples
#' \donttest{
#' n=10^2; locs=cbind(runif(n),runif(n))
#' covparms=c(1,.1,.5); nuggets=rep(.1,n)
#' Sigma=exp(-fields::rdist(locs)/covparms[2])+diag(nuggets)
#' z=as.numeric(t(chol(Sigma))%*%rnorm(n));
#' data=z+1
#' vecchia.est=vecchia_estimate(data,locs,theta.ini=c(covparms,nuggets[1]))
#' n.p=30^2; grid.oneside=seq(0,1,length=round(sqrt(n.p)))
#' locs.pred=as.matrix(expand.grid(grid.oneside,grid.oneside))
#' vecchia.pred=vecchia_pred(vecchia.est,locs.pred)
#' }
#' @export
vecchia_pred=function(vecchia.est,locs.pred,X.pred,m=30,...) {

  ## specify vecchia approximation
  vecchia.approx=vecchia_specify(vecchia.est$locs,m,locs.pred=locs.pred,...)

  ## compute predictions
  theta.hat=vecchia.est$theta.hat
  n.par=length(theta.hat)
  preds=vecchia_prediction(vecchia.est$z,vecchia.approx,
                           theta.hat[-n.par],theta.hat[n.par])

  ## add back the trend if possible
  if(!missing(X.pred)){
    mu.pred=preds$mu.pred+X.pred%*%vecchia.est$beta.hat
  } else if(vecchia.est$trend=='none'){
    mu.pred=preds$mu.pred
  } else if(vecchia.est$trend=='constant'){
    mu.pred=preds$mu.pred+vecchia.est$beta.hat
  } else {
    mu.pred=preds$mu.pred
    warning(paste0('X.pred was not specified, so no trend was ',
                   'added back to the predictions'))
  }

  ## return mean and variance at prediction locations
  return(list(mean.pred=mu.pred,var.pred=preds$var.pred))

}

