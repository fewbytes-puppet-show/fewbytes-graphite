class graphite ( 
	$database_type = "sqlite3",
	$database_host = "",
	$database_port = "",
	$database_name = "/opt/graphite/storage/webapp.sqlite3",
	$time_zone = "Etc/UTC"
) {
	include "apache"
	include python::python26
	include apache::mod::wsgi
	$apache_log_dir = $::osfamily ? { 
		debian => "/var/log/apache2",
		default => "/var/log/httpd",
	}
	
	$dir = "/opt/graphite"
	$webapp_dir = "$dir/webapp"
	$conf_dir = "$dir/conf"
	$storage_dir = "$dir/storage"

	$graphite_user = $operatingsystem ? {
		/CentOS|RedHat|Fedora/ => "apache",
		default => "www-data"
    }
	Package <| provider == pip |> { require => Class[python::python26]}
	package { ["whisper", "carbon", "graphite-web"]:
		provider => "pip",
		ensure => present
	}
	package {["django", "django-tagging", "python-memcached"]:
		provider => "pip",
		ensure => present,
	}
	package {$operatingsystem ? {
		/CentOS|RedHat|Fedora/ => "cairo-devel",
		default => "libcairo-dev"
    }: }
	->
	package {"pycairo":
		ensure => "1.8.8",
		provider => "pip"
	}
	if ($operatingsystem =~ /RedHat|CentOS/) {
		$arch_libdir = $architecture ? {
			"x86_64" => "/usr/lib64",
			default => "/usr/lib"
		}
		file {"$arch_libdir/python2.6/site-packages/cairo/__init__.py":
			content => "from _cairo import *",
			mode => 644,
			require => Package["pycairo"]
		}
	}
	file {"$webapp_dir/graphite.wsgi":
		content => template("graphite/graphite.wsgi.erb"),
		mode => 644,
		notify => Service[httpd],
		require => [Package[graphite-web], Class[apache::mod::wsgi]]
	}
	apache::vhost {"graphite":
		port => 80,
		ssl => false,
		servername => "graphite.$domain",
		serveradmin => "webmaster@$fqdn",
		template => "graphite/apache-graphite.conf.erb",
		docroot => "$dir/webapp",
		require => Package["graphite-web"]
	}
	file {"$conf_dir/storage-schemas.conf":
		ensure => file,
		content => template("graphite/storage-schemas.conf.erb"),
		mode => 644,
		require => Package["carbon"]
	}
	file {["$storage_dir", "$storage_dir/whisper", "$storage_dir/rrd", "$storage_dir/log", "$storage_dir/log/webapp"]:
		ensure => directory,
		mode => 644,
		owner => $graphite_user,
		require => Package["carbon"]
	}

	file {"$webapp_dir/graphite/local_settings.py":
		ensure => file,
		mode => 644,
		notify => Service[httpd],
		content => template("graphite/local_settings.py.erb")
	}
	file {"/var/log/graphite":
		owner => $graphite_user,
	}

	if $database_type == "sqlite3" {
		exec {"graphite syncdb":
			command => "python manage.py syncdb",
			user => $graphite_user,
			cwd => "$webapp_dir/graphite",
			path => "/usr/bin:/usr/local/bin",
			creates => "$database_name",
			require => File["$webapp_dir/graphite/local_settings.py"]
		}
	}
	file {"/var/log/graphite/carbon-cache":
		owner => $graphite_user,
	}
	->
	file {"$conf_dir/carbon.conf":
		content => template("graphite/carbon.conf.erb"),
		mode => 644
	}
	->
	runit::service {"carbon-cache":
		enable => true,
		rundir => "$dir/",
		logdir => "/var/log/graphite/carbon-cache",
		command => "$dir/bin/carbon-cache.py --debug start",
		require => File["$conf_dir/storage-schemas.conf"]
	}
}
