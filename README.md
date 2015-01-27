Capsize-- Trackable, Web-based Capistrano Deployments
===============================================

About
-----

Capsize is a web-based GUI for managing Capistrano deployments.  Capsize allows you to override configuration variables associated with a project on a per environment basis, so you can customize deployment targets based on environments like production, stage, test, and development. 
  
Capsize will also allow you to create different user accounts with permission grants to deploy different projects.  You may also include custom recipes and export Capfiles to be run from the command-line.


Installation
------------

### 1. Clone

git clone git@github.com:webonise/capsize.git

### 2. Dependencies

Install all gem dependencies via the gem bundler:

```bash
> bundle install
```

### 3. Configuration

Copy `config/capsize_config.rb.sample` to `config/capsize_config.rb` and edit appropriatly.  
In this configuration file you can set the mail settings of Capsize.

Generate a file (`config/initializers/session_store.rb`) with a random secret used to secure session data :

```bash
> bundle exec rake generate_session_store
```

### 4. Database

Copy `config/database.yml.sample` to `config/database.yml` and edit to point to the relational database of your choice.  You need at least the production database defined in your yml.  The others are optional entries for development and testing.

Then create the database structure with Rake:

```bash
> bundle exec rake db:migrate RAILS_ENV=production
```

### 5. Start Capsize  

```bash
> bundle exec thin -e production start
```

Capsize is then available at http://host:3000/

The default user is `admin`, the password is `admin`.  
Please change the password after the first login.

Planned New Features
------------

Capistrano 3 Support

Group-based permissions

Maintainer
-----------

Webonise Lab
  
Original Author
------

Jonathan Weiss, formerly of Peritor, was kind enough to author the parent of Capsize, Capsize.  We are delighted to be able to maintain and modernize this tool at Webonise.

Contributor
-----------

Jérôme Macias

  
License
-------

BSD, see LICENSE.txt
