library("MASS")
rm(list=ls())

min.year = 1951
max.year = 2013

clim.jun2nov = data.frame(row.names=as.character(min.year:max.year))
# clim.mar2may = data.frame(row.names=as.character(min.year:max.year))
# clim.jun2aug = data.frame(row.names=as.character(min.year:max.year))

## Load climate index data as predictors
for (f in list.files(path="data", pattern="*.data")) {
  #   print(f)
  clim = read.table(file.path("data", f), skip=1, row.names=1, nrows=66)
  colnames(clim) = month.abb
  cname = sub(".data", "", f)
  clim.jun2nov[, cname] = scale(rowMeans(clim[as.character(min.year:max.year), 6:11]))
#   clim.mar2may[, cname] = scale(rowMeans(clim[as.character(min.year:max.year), 3:5]))
#   clim.jun2aug[, cname] = scale(rowMeans(clim[as.character(min.year:max.year), 6:8]))
}

## Load hurricane count data as the dependent variable
hurdat = read.csv("data/hurdat.csv", row.names=1)
hur.count = hurdat[as.character(min.year:max.year), "RevisedHurricanes"]
# par(mfrow=c(1, 1))
# hist(hur.count, breaks=seq(1.5, 15.5), main="Histogram of Hurricane Counts per Year",
#      xlab = "Annual Hurricane Count")

## Check the distribution of the count data
# library(vcd)
# fit = goodfit(df$hur.count, type="poisson")
# summary(fit)
# rootogram(fit)
# distplot(hur.count, type="poisson")

## Poisson regression with best subset stepwise variable selection
par(mfrow=c(1,1))
pdf("results/histogram_counts.pdf")
hist(hur.count, breaks=10, main="Histogram of Hurricane Counts per Year", xlab = "Hurricanes")
dev.off()

## Poisson regression with best subset stepwise selection
df = cbind(hur.count, clim.jun2nov)
glm.full = glm(hur.count ~ ., data=df, family=poisson)
summary(glm.full)
glm.stepwise = step(glm.full, direction="both") #, k=log(length(hur.count)))
summary(glm.stepwise)
# anova(glm.full, glm.stepwise)

## Check over/under-dispersion
summary(glm(formula(glm.stepwise), data=df, family=quasipoisson))

## Check for outliers on the stepwise-selected model
par(mfrow=c(2,2))
for (i in 1:4)
  plot(glm.stepwise, which=i)

## Check for outliers on the full model
pdf("results/assumptions.pdf")
par(mfrow=c(2,2))
for (i in 1:4)
  plot(glm.full, which=i)
dev.off()

## Goodness of fit test (between the fitted model and saturated model)
### Residual Deviance
p.value = pchisq(glm.stepwise$deviance, glm.stepwise$df.residual, lower.tail=FALSE)
print(paste("Goodness of fit test (Residual Deviance): p-value =", p.value)) # Large p-value indicates good fit.

### Pearson test
p.value <- pchisq(sum(residuals(glm.stepwise, type="pearson")^2 ),
                  glm.stepwise$df.residual, lower.tail=FALSE)
print(paste("Goodness of fit test (Pearson): p-value =", p.value)) # Large p-value indicates good fit.

## Likelihood ratio test (between the fitted model and null model)
p.value = pchisq(glm.stepwise$null.deviance-glm.stepwise$deviance,
                 glm.stepwise$df.null-glm.stepwise$df.residual, lower.tail=FALSE)
print(paste("Likelihood ratio test: p-value =", p.value)) # Small p-value indicates not all betas are zero.

# glm.stepwise = glm(hur.count ~ tna + poly(nina3, degree=2, raw=TRUE), data=df, family=poisson)

## Residual plots
par(mfrow=c(2, 2))
pdf("results/residuals.pdf")
plot(resid(glm.subset, type="response") ~ predict(glm.subset, type="response"),
     xlab=expression(hat(lambda)), ylab="Response residuals")
abline(h=0)
plot(resid(glm.stepwise, type="response") ~ predict(glm.stepwise, type="link"),
     xlab=expression(paste(hat(eta), " = X", hat(beta))), ylab="Response residuals")
abline(h=0)
plot(resid(glm.stepwise, type="deviance") ~ predict(glm.stepwise, type="link"),
     xlab=expression(paste(hat(eta), " = X", hat(beta))), ylab="Deviance residuals")
abline(h=0)
plot(resid(glm.stepwise, type="pearson") ~ predict(glm.stepwise, type="link"),
     xlab=expression(paste(hat(eta), " = X", hat(beta))), ylab="Pearson residuals")
abline(h=0)

## Smooth Scatter Plots
scatter.smooth(df$tna, df$hur.count)
scatter.smooth(df$nina3, df$hur.count)
lambda = predict(glm.stepwise, type="response")
z = predict(glm.stepwise) + (df$hur.count-lambda)/lambda
scatter.smooth(df$tna, z, ylab="Linearized response")
scatter.smooth(df$nina3, z, ylab="Linearized response")
# scatter.smooth(predict(glm.stepwise), z, ylab="Linearized response")

## Autocorrelation in deviance residuals
par(mfrow=c(1, 1))
acf(resid(glm.stepwise, type="deviance"))

## Poisson regression with lasso variable selection
library("glmnet")
x = model.matrix(hur.count ~ ., data=df)[, -1]
y = df$hur.count
grid <- 10^seq(10, -2, length=100)
fit.lasso = glmnet(x, y, family="poisson", alpha=1, lambda=grid)
set.seed(123)
bestlam = cv.glmnet(x, y, family="poisson", nfolds=5)$lambda.min
beta = as.vector(predict(fit.lasso, type="coefficients", s=bestlam))[-1]
glm.lasso = glm(y ~ x[, beta!=0], family=poisson)

## Variable selection via best subset glm from the selected variables via lasso.
library(bestglm)
glm.best.bic = bestglm(cbind(clim.jun2nov[, beta!=0], y=hur.count), family=poisson)
glm.best.aic = bestglm(cbind(clim.jun2nov[, beta!=0], y=hur.count), family=poisson, IC="AIC")
set.seed(123)
glm.best.cv = bestglm(cbind(clim.jun2nov[, beta!=0], y=hur.count), family=poisson,
                      IC="CV", CVArgs=list(Method="HTF", K=5, REP=1))
acf(resid(glm.subset, type="deviance"))

# ## Poisson regression with lasso variable selection
# library("glmnet")
dev.off()

## Smooth Scatter Plots
par(mfrow=c(1,2))
pdf("results/smooth_scatter.pdf")
scatter.smooth(df$tna.data, df$hur.count)
scatter.smooth(df$nina3.data, df$hur.count)
dev.off()


## Poisson regression with lasso variable selection
x <- model.matrix(hur.count ~ ., data=df)[, -1]
y <- df$hur.count
grid <- 10^seq(10, -2, length=100)
fit.lasso <- glmnet(x, y, family="poisson", alpha=1, lambda=grid)
bestlam <- cv.glmnet(x, y, family="poisson", nfolds=5)$lambda.min
beta <- as.vector(predict(fit.lasso, type="coefficients", s=bestlam))

## Variable selection via best subset glm from the selected variables via lasso.
library(bestglm)
glm.best = bestglm(cbind(clim.jun2nov[, beta!=0], y=hur.count), family=poisson)
#glm.best = bestglm(cbind(clim.jun2nov[, beta!=0], y=hur.count), family=poisson, IC="AIC")
#glm.best = bestglm(cbind(clim.jun2nov[, beta!=0], y=hur.count), family=poisson,
#                  IC="CV", CVArgs=list(Method="HTF", K=5, REP=1))

glm.best
paste("BIC for lasso exhaustive selection=", BIC(glm.best$BestModel))
paste("BIC for stepwise selection=", BIC(glm.stepwise))

pdf("results/lassomodelassumptions.pdf")
par(mfrow=c(2,2))
for (i in 1:4)
  plot(glm.best, which=i)
dev.off()
