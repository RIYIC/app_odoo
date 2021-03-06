include_recipe "app_odoo::default"

extra_packages = %w{
    libfreetype6
    libxrender1
    fonts-dejavu-core
    ttf-bitstream-vera
    fonts-freefont-ttf
    gsfonts-x11
    gsfonts
    xfonts-75dpi
    xfonts-base
    xfonts-utils
    libfontenc1
    libxfont1
    x11-common
    xfonts-encodings
    libxml2-dev
    libxslt-dev
    libsasl2-dev
    libldap2-dev
    libssl-dev
    libjpeg-dev
    libpng-dev
    fontconfig-config
    fontconfig

}

# instalamos todos os paquetes do sistema necesarios
extra_packages.each do |p|
    package p
end

# instalamos a ultima version de wkhtmltox 
# ollo que tenhen que estar instalados os paquetes necesarios no sistema, senon casca
package_path = "/tmp/wkhtmltopdf.deb"

remote_file package_path do
    #source "#{node['app']['odoo']['wkhtmltopdf']['download_url']}/#{latest_version}/wkhtmltox-#{latest_version}_linux-trusty-amd64.deb"
    source node['app']['odoo']['wkhtmltopdf']['download_url'].call
    action :create_if_missing
    backup false
end

dpkg_package "wkhtmltopdf.deb" do
    source      package_path 
    action      :install
end

# facemos o deploy de todas as apps de odoo que nos pasen
node["app"]["odoo"]["installations"].each do |app|

    owner = app["user"] || node["app"]["odoo"]["default_user"]
    group = app["group"] || 'users'

    # instalamos a aplicacion e configuramos os servicios necesarios
    wsgi_app app["domain"] do

        server_alias       app["alias"]
        target_path        "#{app["target_path"]}/odoo-server"
        environment        app["environment"]
        entry_point        "openerp-wsgi.py"
        action             :deploy
        owner              owner        
        group              group
        timeout            "600"
    
        repo_url           app["repo_url"] || node["app"]["odoo"]["default_repo_url"]
        repo_type          app["repo_type"] || node["app"]["odoo"]["default_repo_type"]
        revision           app["revision"] || node["app"]["odoo"]["default_revision"]
        repo_depth         1
        purge_target_path  'yes'
        processes          1
        threads            4
        requirements_file  'requirements.txt'
        extra_modules      %w{unidecode}

        notifies          :restart, 'service[nginx]'
    
    end

    # seica deben ir con rutas relativas dende o directorio do odoo-server
    addons_path = ["./addons"]

    # creamos o directorio para a sesion e demais data
    directory app["data_dir"] do
        user        owner
        group       group
        recursive   true
        action      :create
    end

    # creamos o directorio para os custom plugins
    directory "#{app["target_path"]}/custom" do
        user    owner
        group   group
        action  :create
    end


    # descargar modulos extra de espanha
    code_repo "#{app['target_path']}/custom/l10n-spain" do
        action              "pull"
        owner               owner
        group               group
        url                 'https://github.com/OCA/l10n-spain.git'
        revision            '8.0'
        depth               1
        purge_target_path   'yes'
    end
    addons_path << "../custom/l10n-spain"


    # descargar modulos de reporting_engine necesarios para os l10n-spain
    code_repo "#{app['target_path']}/custom/reporting-engines" do
        action              "pull"
        owner               owner
        group               group
        url                 'https://github.com/OCA/reporting-engines'
        revision            '8.0'
        depth               1
        purge_target_path   'yes'
    end
    addons_path << "../custom/reporting-engines"


    # descargar modulos extra account-financial-tools necesarios para l10n-spain
    code_repo "#{app['target_path']}/custom/account-financial-tools" do
        action              "pull"
        owner               owner
        group               group
        url                 'https://github.com/OCA/account-financial-tools'
        revision            '8.0'
        depth               1
        purge_target_path   'yes'
    end
    addons_path << "../custom/account-financial-tools"


    # descargar modulos extra partner-contact necesarios para l10n-spain
    code_repo "#{app['target_path']}/custom/partner-contact" do
        action              "pull"
        owner               owner
        group               group
        url                 'https://github.com/OCA/partner-contact'
        revision            '8.0'
        depth               1
        purge_target_path   'yes'
    end
    addons_path << "../custom/partner-contact"
    
    # por ultimos agregamos modulo para evitar que odoo este solicitando continuamente a vinculacion 
    # con odoo.com
    directory "#{app["target_path"]}/custom/other" do
        user    owner
        group   group
        action  :create
    end

    code_repo "#{app['target_path']}/custom/other/oerp_no_phoning_home" do
        action      :pull
        owner       owner
        group       group
        url         'https://bitbucket.org/BizzAppDev/oerp_no_phoning_home.git'
        revision    'master'
    end
    addons_path << "../custom/other"


    
    # creamos o ficheiro de configuracion
    template "#{app['target_path']}/odoo-server/openerp-wsgi.py" do
        source      'openerp-wsgi.py.erb'
        cookbook    "app_odoo" 
        user        owner
        group       group
        variables(
                    :addons_path => addons_path,
                    :admin_passwd => app['admin_password'],
                    :data_dir   => app['data_dir'],
                    :db_name => app['db_name'],
                    :db_user => app['db_user'],
                    :db_password => app['db_password'],
                    :db_host => app['db_host']
        )
                    
    end


    # creamos unha extra task para forzar o propietario do volumen do data_dir
    # dentro dun container
    if node["riyic"]["inside_container"]

        file "#{node['riyic']['extra_tasks_dir']}/#{app['domain']}-odoo_deploy.sh" do
            mode '0700'
            owner 'root'
            group 'root'
            content "chown -R #{owner}:#{group} #{app['data_dir']}"
        end

    end


end
