require_relative '../modules/williamhill_live'
namespace :williamhill do
  namespace :import do
    task :live do
      parser = WilliamhillLive.new()
      parser.parse()
    end
  end
end
