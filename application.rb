require 'rubygems'
require 'sinatra'
require 'httparty'
require 'pp'
include ERB::Util # Make url encode methods available

set :sessions, true # Support for encrypted, cookie-based sessions

class Tmdb
  
  include HTTParty
  
  def self.api_url
    "http://api.themoviedb.org/2.1/"
  end
  
  def self.api_key
    "c54eff606fc1f4e27314d565c36c68fc"
  end
  
  def send_request(http_method, path, params)
    self.class.send(http_method, "#{self.class.api_url}#{path}#{self.class.api_key}/#{params}")["OpenSearchDescription"]["movies"]["movie"]
  end
  
  def search(query)
    raise ArgumentError if query.blank?
    results = send_request(:get, "Movie.search/en/xml/", url_encode(query)) rescue []
    #raise results.inspect
    movies = []
    results.each do |result|
      movies << Movie.new(result)
    end
    movies
  end
  
  def get_info(tmdb_id)
    raise send_request(:get, "Movie.getInfo/en/xml/", tmdb_id).inspect
    @movie = Movie.new(send_request(:get, "Movie.getInfo/en/xml/", tmdb_id))    
  end
  
end

class Movie
  
  attr_accessor :name, :overview, :language, :cover_url, :thumb_url, :year, :tmdb_id
  
  def initialize(attrs = {})  
    self.name = attrs["name"]
    self.overview = attrs["overview"]
    self.language = attrs["language"]
    self.cover_url = (attrs["images"]["image"].select{ |img| img["size"] == "cover"  }.first["url"] rescue nil)
    self.thumb_url = (attrs["images"]["image"].select{ |img| img["size"] == "thumb"  }.first["url"] rescue nil)
    self.year = Time.parse(attrs["released"]).year rescue nil
    self.tmdb_id = attrs["id"]
    self.director = attrs[""] rescue nil
    self.duration = attrs[""] rescue nil
    self.certification = attrs[""]
  end
  
  def to_s
    name
  end
  
end

get '/' do
  erb :index
end

get '/results' do
  session[:search_query] = params[:search_query] if params[:search_query]
  @movies = Tmdb.new.search(session[:search_query])
  erb :results
end

get '/result' do
  @movie = Tmdb.new.get_info(params[:tmdb_id])
  erb :result
end
