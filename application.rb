require 'rubygems'
require 'sinatra'
require 'httparty'
require 'active_record'
require 'indextank'
include ERB::Util # Make url encode methods available

set :sessions, true # Support for encrypted, cookie-based sessions

class IndexTankClient
  
  def initialize
    client = IndexTank::Client.new(ENV['INDEXTANK_API_URL'] || 'http://:bqwcRdvFEHcyWB@d3hfo.api.indextank.com')
    @index = client.indexes('idx')
  end
  
  def add(movie)
    attrs = movie.attributes
    attrs.merge!({:timestamp => Time.now.to_i})
    @index.document(movie.tmdb_id).add(attrs)
  end
  
  def search(query)
    results = @index.search("name:#{query}", :fetch => Movie.new.attributes.keys.join(",") )["results"]
    movies = []
    results.each do |result|
      movies << Movie.new(result)
    end
    movies
  end
  
end

class Tmdb
  
  include HTTParty
  
  class Error < RuntimeError; end
  class ApiMethodNotImplemented < Error; end
  
  def self.api_url
    "http://api.themoviedb.org/2.1/"
  end
  
  def self.api_key
    "c54eff606fc1f4e27314d565c36c68fc"
  end
  
  def send_request(http_method, api_method, params)
    path = case api_method
    when :search
      "Movie.search"
    when :get_info
      "Movie.getInfo"
    when :imdb_lookup
      "Movie.imdbLookup"
    else
      raise ApiMethodNotImplemented
    end
    
    self.class.send(http_method, "#{self.class.api_url}#{path}/en/xml/#{self.class.api_key}/#{params}")["OpenSearchDescription"]["movies"]["movie"]
  end
  
  def search(query)
    raise ArgumentError if query.blank?
    results = send_request(:get, :search, url_encode(query))
    movies = []
    results.each do |result|
      movies << Movie.new(result)
    end
    movies
  end
  
  def get_info(tmdb_id)
    Movie.new(send_request(:get, :get_info, tmdb_id))    
  end
  
  def imdb_lookup(imdb_id)
    Movie.new(send_request(:get, :imdb_lookup, imdb_id))
  end
  
end

class Movie
  
  attr_accessor :name, :overview, :language, :cover_url, :thumb_url, :year, :tmdb_id, :duration, :certification, :imdb_id, :genres
  
  def initialize(attrs = {})  
    self.name = attrs["name"]
    self.overview = attrs["overview"]
    self.language = attrs["language"]
    self.cover_url = (attrs["images"]["image"].select{ |img| img["size"] == "cover"  }.first["url"] rescue nil)
    self.thumb_url = (attrs["images"]["image"].select{ |img| img["size"] == "thumb"  }.first["url"] rescue nil)
    self.year = Time.parse(attrs["released"]).year rescue nil
    self.tmdb_id = attrs["id"]
    self.imdb_id = attrs["imdb_id"]
    self.duration = attrs["runtime"] rescue nil
    self.certification = attrs["certification"] rescue nil
    self.genres = attrs["categories"]["category"].map{ |c| c["name"] }.sort.join(", ") rescue nil
  end
  
  def self.attributes
    
  end
  
  def to_s
    name
  end
  
  def attributes
    attrs = {}
    self.instance_variables.each do |v|
      attrs[v.gsub("@", "").to_sym] = self.instance_variable_get(v)
    end
    attrs
  end
  
  def self.genres
    ["Action", "Adventure", "Animation", "Comedy", "Crime", "Disaster", "Documentary", "Drama", "Eastern", "Family", "Fantasy", "History", "Holiday", "Horror", "Musical", "Mystery", "Romance", "Science Fiction", "Thriller", "War", "Western"]
  end
  
end

get '/' do
  erb :index
end

get '/results' do
  session[:search_query] = params[:search_query] if params[:search_query]
  #@movies = Tmdb.new.search(session[:search_query])
  @movies = IndexTankClient.new.search(session[:search_query])
  raise @movies.inspect
  erb :results
end

get '/result' do
  @movie = if params[:tmdb_id] 
    Tmdb.new.get_info(params[:tmdb_id])
  elsif params[:imdb_id]
    Tmdb.new.imdb_lookup(params[:imdb_id])
  end
  erb :result
end

get '/add' do
  erb :add
end

post '/create' do
  IndexTankClient.new.add(Tmdb.new.imdb_lookup(params[:imdb_id])) if params[:imdb_id]
  redirect "/"
end
