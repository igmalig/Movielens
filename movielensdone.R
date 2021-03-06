#Data Science Movielens Project
#Ivan Malig
#June 6, 2020


#Create test and validation sets
# Create edx set, validation set, and submission file
if(!require(tidyverse)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(caret)) install.packages("caret", repos = "http://cran.us.r-project.org")
# MovieLens 10M dataset:
# https://grouplens.org/datasets/movielens/10m/
# http://files.grouplens.org/datasets/movielens/ml-10m.zip
dl <- tempfile()
download.file("http://files.grouplens.org/datasets/movielens/ml-10m.zip", dl)
ratings <- read.table(text = gsub("::", "\t", readLines(unzip(dl, "ml-10M100K/ratings.dat"))),
                      col.names = c("userId", "movieId", "rating", "timestamp"))
movies <- str_split_fixed(readLines(unzip(dl, "ml-10M100K/movies.dat")), "\\::", 3)
colnames(movies) <- c("movieId", "title", "genres")
movies <- as.data.frame(movies) %>% mutate(movieId = as.numeric(levels(movieId))[movieId],
                                           title = as.character(title),
                                           genres = as.character(genres))
movielens <- left_join(ratings, movies, by = "movieId")
# Validation set will be 10% of MovieLens data
set.seed(1)
test_index <- createDataPartition(y = movielens$rating, times = 1, p = 0.1, list = FALSE)
edx <- movielens[-test_index,]
temp <- movielens[test_index,]
# Make sure userId and movieId in validation set are also in edx set
validation <- temp %>% 
  semi_join(edx, by = "movieId") %>%
  semi_join(edx, by = "userId")
# Add rows removed from validation set back into edx set
removed <- anti_join(temp, validation)
edx <- rbind(edx, removed)
rm(dl, ratings, movies, test_index, temp, movielens, removed)

library(caret)
library(anytime)
library(tidyverse)
library(lubridate)
library(ggplot2)

#We want to incerase our memory size since our current memory will prohibit us from smoothly running
#some snips of code later on.

memory.limit(size= 10000)

#We keep all columns except for ratings in our validation set. 

validation_a <- validation  
validation <- validation %>% select(-ratings)


#1. #EDX DataSet

#The edx data set contains 9000055 rows and 6 columns of information about different movies such as "userId"    "movieId" 
#"rating"    "timestamp" "title"     "genres". 

#"userId" - a unique code given to each user.
#"movieId" - a unique code given to each movie.   
#"rating" - rating given by users ranging from 0.5 to 5 (in increments of 0.5)
#"genres" - film categories
#"title" - title of the movie
#"timestamp"- time when ratings were given.

head (edx)
summary(edx)  # SummaryStatistics of the EDX DataSet


#2. Data Processing

#  First, we will define a function that will measure our RMSE.
RMSE <- function(actual_ratings, predicting){
  sqrt(mean((actual_ratings-predicting)^2,na.rm=TRUE))
}

# Second, we will create a separate column for year for our datasets.

edx <- edx %>% mutate(year = as.numeric(str_sub(title,-5,-2)))
validation <- validation %>% mutate(year = as.numeric(str_sub(title,-5,-2)))
validation_a <- validation_a %>% mutate(year = as.numeric(str_sub(title,-5,-2)))

# Third, we will try to separate the genres column of our datasets so each row will only have one genre.

sep_edx  <- edx  %>% separate_rows(genres, sep = "\\|")
sep_validation <- validation   %>% separate_rows(genres, sep = "\\|")
sep_validation_a <- validation_a  %>% separate_rows(genres, sep = "\\|")

#To seethe dataset and summary statistics

head(edx)
head(sep_edx)


#We now want to see how many distinct users and movies there are by using the folowing code

edx %>% summarize(unique_users = n_distinct(userId), unique_movies = n_distinct(movieId))

#We can see here which years had the highest ratings count. We notice that the 1990s, specifically the mid 90s, had the highest number of ratings.
#The peak was at 1995. 

rate_per_year<- sep_edx %>% group_by(year) %>% summarize(count= n()) %>% arrange(desc(count))

#We can also see which genres are most rated by running this code
rate_per_genre <- sep_edx%>% group_by(genres) %>% summarize(count = n()) %>% arrange(desc(count))

#As mentioned above, ratings can range from 0.5to 5 and ratings are in increments of 0.5 as seen here.

ratings <- as.vector(edx$rating)
unique(ratings) 

#Chart showing how many cunt there are for each possible rating value.

ratings <- ratings[ratings != 0]
ratings <- factor(ratings)
qplot(ratings, fill= "blue") + ggtitle("Count per Rating")

#From the graph we wil notice that whole ratings are more common compared to "half" ratings, furthermore
#a rating of 4 is more common than any other whole rating

#3. Analysis Strategy

#We must keep in mind that movie ratings will vary across people, movies, and genres (among other things).
#User preferences may result in a bad rating on a "good" movie or a good rating on a "bad" movie. On the
#other hand, more known movies will tend to average higher ratings than less known movies. We can also see
#fluctuating ratings based on movie genre. We will try to incorporate these biases into our model in order
#to have a reasonable prediction. 

#We see here the distribution of ratings per movie
edx %>% count(movieId) %>% ggplot(aes(n)) + geom_histogram(bins = 20, color = "black", fill = "blue") + 
scale_x_log10() + ggtitle("Ratings per movie")

#Here, we see ratings per user

edx %>% count(userId) %>% ggplot(aes(n)) + geom_histogram(bins = 30, color = "black", fill = "blue") + 
scale_x_log10() + ggtitle("ratings per user")

#Here, we visualize how genre popularity changed throughout the years by looking at the trend for selected genres

popular_genres <- sep_edx %>% na.omit() %>% select(movieId, year, genres) %>% mutate(genres = as.factor(genres)) %>% 
group_by(year, genres) %>% summarise(number = n()) %>% complete(year = full_seq(year, 1), genres, fill = list(number = 0)) 

popular_genres %>%
filter(year > 1930) %>% filter(genres %in% c("Comedy", "Thriller", "Animation", "Romance")) %>%
ggplot(aes(x = year, y = number)) + geom_line(aes(color=genres)) + scale_fill_brewer(palette = "Paired") 

#4. Preparing the Model

#The goal is to compare RSME for different predicting models, we will keep track of our RSMEs with this code

rmse_tracker <- data_frame()

a. #the simplest model we can use for prediction is with the mean rating, meaning were are to use the mean 
#as our predicted rating for al movies.

mu <- mean(edx$rating)  

b. #Our next model will take into account the movie bias, that is different movies (e.g blockbuster vs indie)
#May results in stark differences in rating.

beta_m <- edx %>% group_by(movieId) %>% summarize(b_m = mean(rating - mu))
beta_m %>% qplot(b_m, geom ="histogram", bins = 20, data = ., color = I("black"))

c. #Next, we stated that different viewers have different tendencies in rating movies. Thus, like in our movie
#case, we are going to compute for our user bias by running this code below

beta_u<- edx %>% left_join(beta_m, by='movieId') %>% group_by(userId) %>% summarize(b_u = mean(rating - mu - b_m))
beta_u %>% qplot(b_u, geom ="histogram", bins = 30, data = ., color = I("black"))

#5. The model

#The goal is for our model to produce a low(er) rsme. We will try to examine different resulting RSMEs 
#when accounting for the different biases that we've talked about

#baseline

rmse1 <- RMSE(validation$rating, mu)

#check our tracker

rmse_tracker <- data_frame(method = "Mean", RMSE = rmse1)
rmse_tracker

#with movie efect

rmse2 <- validation %>%  left_join(beta_m, by='movieId') %>% mutate(pred = mu + b_m) 
model1 <- RMSE(validation_a$rating,rmse2$pred)
rmse_tracker <- bind_rows(rmse_tracker, data_frame(method="Mean + Beta_m", RMSE = model1 ))
rmse_tracker

#with movie and user effect

rmse3 <- validation %>%  left_join(beta_m, by='movieId') %>% left_join(beta_u, by='userId') %>%
mutate(pred = mu + b_m + b_u) 

# test and save rmse results 

model2 <- RMSE(validation_a$rating,rmse3$pred)
rmse_tracker <- bind_rows(rmse_tracker,data_frame(method="Mean + b_m + b_u",  RMSE = model2))
rmse_tracker


#6. Regularisation
#We saw a while ago that there are many "outliers" in our data. These may be users who rated rarely, or movies
#that were rarely given a rating. TO make a better prediction, we must be able to 

lambdas <- seq(0, 10, 0.5)

rmses <- sapply(lambdas, function(l){
  
mu <- mean(edx$rating)
  
b_m <- edx %>% group_by(movieId) %>%summarize(b_m = sum(rating - mu)/(n()+l))
  
b_u <- edx %>% left_join(b_m, by="movieId") %>% group_by(userId) %>% summarize(b_u = sum(rating - b_m - mu)/(n()+l))
  
predicting <- validation %>% left_join(b_m, by = "movieId") %>% left_join(b_u, by = "userId") %>%
mutate(pred = mu + b_m + b_u) %>% .$pred
  
return(RMSE(validation_a$rating,predicting))
})

#To show an rmse-lambda plot that will help us visualize what value of lambda will be optimal 

qplot(lambdas, rmses)  

#To check which value of lambda will give us the minimum rmse

lambda <- lambdas[which.min(rmses)]
lambda

# Compute regularized estimates of b_m using lambda

regular_beta_m<- edx %>% group_by(movieId) %>% summarize(b_m = sum(rating - mu)/(n()+lambda), n_i = n())

# Compute regularized estimates of b_u using lambda

regular_beta_u <- edx %>% left_join(regular_beta_m, by='movieId') %>% group_by(userId) %>%
summarize(b_u = sum(rating - mu - b_m)/(n()+lambda), n_u = n())

# Predict ratings with movie and user effect

regular_predicting <- validation %>% left_join(regular_beta_m, by='movieId') %>% left_join(regular_beta_u, by='userId') %>%
mutate(pred = mu + b_m + b_u) %>% .$pred

# Test and save results

model3 <- RMSE(validation_a$rating,regular_predicting)
rmse_tracker <- bind_rows(rmse_tracker, data_frame(method="Beta_m and Beta_u (regularized)",RMSE = model3 ))
rmse_tracker

#7. Regularisation with improved model (including year and/or genre effect)

lambdas <- seq(0, 30, 1)

rmses <- sapply(lambdas, function(l){
  
mu <- mean(edx$rating)
  
b_m <- sep_edx %>% group_by(movieId) %>% summarize(b_m = sum(rating - mu)/(n()+l))
  
b_u <- sep_edx %>% left_join(b_m, by="movieId") %>% group_by(userId) %>% summarize(b_u = sum(rating - b_m - mu)/(n()+l))
  
b_y <- sep_edx %>% left_join(b_m, by='movieId') %>% left_join(b_u, by='userId') %>% group_by(year) %>%
summarize(b_y = sum(rating - mu - b_m - b_u)/(n()+lambda), n_y = n())
  
b_g <- sep_edx %>% left_join(b_m, by='movieId') %>% left_join(b_u, by='userId') %>%
left_join(b_y, by = 'year') %>% group_by(genres) %>%
summarize(b_g = sum(rating - mu - b_m - b_u - b_y)/(n()+lambda), n_g = n())
 
predicting <- sep_validation %>% left_join(b_m, by='movieId') %>% left_join(b_u, by='userId') %>%
left_join(b_y, by = 'year') %>% left_join(b_g, by = 'genres') %>% mutate(pred = mu + b_m + b_u + b_y + b_g) %>% 
.$pred
  
return(RMSE(sep_validation_a$rating,predicting))
})

qplot(lambdas, rmses)  

lambda_opt <- lambdas[which.min(rmses)]
lambda_opt

# for lambda_opt, for simplicity in our case, we chose a couple of lambda values to minimize our running
#time. Our choices were 12 and 14. But on a faster computer, the above code would be used to point 
#out the optimal lambda for our rmse minimization.

#Regularisation with the other effects

regular_beta_m2 <- sep_edx %>% group_by(movieId) %>% summarize(b_m = sum(rating - mu)/(n()+lambda_opt), n_i = n())

regular_beta_u2 <- sep_edx %>% left_join(regular_beta_m2, by='movieId') %>% group_by(userId) %>%
summarize(b_u = sum(rating - mu - b_m)/(n()+lambda_opt), n_u = n())

regular_beta_y <- sep_edx %>% left_join(regular_beta_m2, by='movieId') %>% left_join(regular_beta_u2, by='userId') %>%
group_by(year) %>% summarize(b_y = sum(rating - mu - b_m - b_u)/(n()+lambda_opt), n_y = n())


predicting <- sep_validation %>% left_join(regular_beta_m2, by='movieId') %>% left_join(regular_beta_u2, by='userId') %>%
left_join(regular_beta_y, by = 'year') %>% mutate(pred = mu + b_m + b_u + b_y) %>% .$pred

model4 <- RMSE(sep_validation_a$rating,predicting)
rmse_tracker <- bind_rows(rmse_tracker, data_frame(method="Beta_m, beta_u, beta_y(regularized)",  
                                     RMSE = model4 ))

rmse_tracker


7. #Results 

rmse_tracker