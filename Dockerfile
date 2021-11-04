FROM ruby:3.0.2

WORKDIR /app

COPY *.rb /app/
COPY *.ryml /app/
COPY Gemfile* /app/

RUN gem install bundler
run bundle update --bundler
RUN bundle install

