FROM ruby:3.4.9-slim-trixie
RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential postgresql-client libpq-dev libyaml-dev libseccomp2 python3 python3-pil poppler-utils tesseract-ocr tesseract-ocr-por tesseract-ocr-eng libreoffice-writer libreoffice-calc libreoffice-impress fonts-dejavu-core ca-certificates curl && rm -rf /var/lib/apt/lists/*
WORKDIR /rails
ENV BUNDLE_PATH=/usr/local/bundle RAILS_LOG_TO_STDOUT=1
COPY Gemfile Gemfile.lock ./
RUN bundle install && groupadd --gid 1000 athenas && useradd --uid 1000 --gid 1000 --create-home athenas
COPY --chown=athenas:athenas . .
RUN mkdir -p storage tmp/mail tmp/pids log /usr/local/share/athenas/lo-profile && chown -R athenas:athenas storage tmp log /usr/local/share/athenas
USER athenas
RUN RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
RUN libreoffice -env:UserInstallation=file:///usr/local/share/athenas/lo-profile --headless --terminate_after_init --nologo --nodefault --norestore
EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
