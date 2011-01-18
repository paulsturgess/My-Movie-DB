require 'rubygems'
require 'sinatra'
require 'httparty'
include ERB::Util # Make url encode methods available

class Tmdb
  
  include HTTParty
  
  def self.api_url
    "http://api.themoviedb.org/2.1"
  end
  
  def self.api_key
    "c54eff606fc1f4e27314d565c36c68fc"
  end
  
  def search(query)
    raise ArgumentError if query.blank?
    results = (self.class.get("#{self.class.api_url}/Movie.search/en/xml/#{self.class.api_key}/#{url_encode(query)}")["OpenSearchDescription"]["movies"]["movie"] rescue [])
    # movies = []
    # results.each do |result|
    #   movies << Movie.new(result)
    # end
  end
  
  def get_info
    
  end
  
end

class Movie
  
  attr_accessor :name, :overview, :language
  
  def initialize(attrs = {})
    attrs.each do |k,v|
      self.send "#{k}=", v
    end
  end
  
end

get '/' do
  erb :index
end

get '/results' do
  @tmdb = Tmdb.new
  @results = @tmdb.search(params[:query]) 
  #raise @results.inspect
  erb :results
end
