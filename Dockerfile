FROM ruby:3.0.3-slim

WORKDIR /app

RUN apt-get update; apt-get install curl python -y

RUN curl https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz > /tmp/google-cloud-sdk.tar.gz

# Installing the package
RUN mkdir -p /usr/local/gcloud \
  && tar -C /usr/local/gcloud -xvf /tmp/google-cloud-sdk.tar.gz \
  && /usr/local/gcloud/google-cloud-sdk/install.sh

# Adding the package path to local
ENV PATH $PATH:/usr/local/gcloud/google-cloud-sdk/bin

COPY *.rb /app/
COPY *.ryml /app/
COPY Gemfile* /app/

RUN gem install bundler
run bundle update --bundler
RUN bundle install

