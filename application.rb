require 'sinatra'
require 'httparty'
require 'active_record'
require 'indextank'
include ERB::Util # Make url encode methods available

set :sessions, true # Support for encrypted, cookie-based sessions

class IndexTankClient
  
  class Error < RuntimeError; end
  class IndexTankApiMethodNotImplemented < Error; end
  
  def initialize
    client = IndexTank::Client.new(ENV['INDEXTANK_API_URL'] || 'http://:bqwcRdvFEHcyWB@d3hfo.api.indextank.com')
    @index = client.indexes('idx')
  end
  
  def add(movie)
    attrs = movie.attributes
    attrs.merge!({:timestamp => Time.now.to_i, :all => "true"})
    @index.document(movie.tmdb_id).add(attrs)
  end
  
  def search(method = :name, query = nil)
    search_terms = case method
    when :imdb_id
      "imdb_id:#{query}"
    when :name
      "name:#{query}"
    when :all
      "all:true"
    else
      raise IndexTankApiMethodNotImplemented
    end
    @index.search(search_terms, :fetch => Movie.new.attributes.keys.join(",") )["results"]
  end
  
  def load(imdb_id)
    search(:imdb_id, imdb_id).first
  end
  
  def all
    search(:all)
  end
  
end

class Tmdb
  
  include HTTParty
  
  class Error < RuntimeError; end
  class TmdbApiMethodNotImplemented < Error; end
  
  def self.api_url
    "http://api.themoviedb.org/2.1/"
  end
  
  def self.api_key
    "c54eff606fc1f4e27314d565c36c68fc"
  end
  
  def self.send_request(http_method, api_method, params)
    path = case api_method
    when :imdb_lookup
      "Movie.imdbLookup"
    else
      raise TmdbApiMethodNotImplemented
    end
    
    send(http_method, "#{self.api_url}#{path}/en/xml/#{self.api_key}/#{params}")["OpenSearchDescription"]["movies"]["movie"]
  end

  def self.imdb_lookup(imdb_id)
    self.send_request(:get, :imdb_lookup, imdb_id)
  end
  
end

class Movie
  
  def self.attributes 
    [:name, :overview, :language, :cover_url, :thumb_url, :year, :tmdb_id, :duration, :certification, :imdb_id, :genres]
  end
  
  self.attributes.each do |attribute|
    attr_accessor attribute
  end
  
  def initialize(attrs = {})
    self.class.attributes.each do |attribute|
      self.send("#{attribute}=", attrs[attribute.to_s])
    end
  end
  
  def self.all
    documents = IndexTankClient.new.all
    documents.inject([]) do |movies, document|
      movies << Movie.convert_from_index_tank(document)
    end
  end
  
  # Grabs movie data from the TMDB api and saves it into the Index Tank store
  def self.add!(imdb_id)
    return false unless imdb_id
    movie = Movie.load_from_imdb_id(imdb_id)
    IndexTankClient.new.add(movie)
  end
  
  # Grabs the movie data from TMDB api and loads
  # the attributes into a movie instance
  def self.load_from_imdb_id(imdb_id) 
    attrs = Tmdb.imdb_lookup(imdb_id)
    movie = Movie.new 
    movie.name = attrs["name"]
    movie.overview = attrs["overview"]
    movie.language = attrs["language"]
    movie.cover_url = (attrs["images"]["image"].select{ |img| img["size"] == "cover"  }.first["url"] rescue nil)
    movie.thumb_url = (attrs["images"]["image"].select{ |img| img["size"] == "thumb"  }.first["url"] rescue nil)
    movie.year = Time.parse(attrs["released"]).year rescue nil
    movie.tmdb_id = attrs["id"]
    movie.imdb_id = attrs["imdb_id"]
    movie.duration = attrs["runtime"] rescue nil
    movie.certification = attrs["certification"] rescue nil
    movie.genres = attrs["categories"]["category"].map{ |c| c["name"] }.sort.join(", ") rescue nil
    movie
  end
  
  # Search for movies in the Index Tank store and
  # returns them as an array of movie instances
  def self.search(query)
    documents = query ? IndexTankClient.new.search(:name, query) : [] #hardcoded to name for now
    documents.inject([]) do |movies, document|
      movies << Movie.convert_from_index_tank(document)
    end
  end
  
  def self.load(imdb_id)
    document = IndexTankClient.new.load(imdb_id)
    Movie.convert_from_index_tank(document)
  end
  
  # Convert an index tank document into a movie instance
  def self.convert_from_index_tank(document)
    Movie.new(document)
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
  response.headers['Cache-Control'] = 'public, max-age=31556926'
  erb :index
end

get '/results' do
  response.headers['Cache-Control'] = 'public, max-age=31556926'
  @movies = Movie.search(params[:search_query])
  redirect "/movie/#{@movies.first.imdb_id}" if @movies.length == 1
  erb :results
end

get '/all' do
  @movies = Movie.all
  erb :results
end

get '/movie/:imdb_id' do
  response.headers['Cache-Control'] = 'public, max-age=31556926'
  @movie = Movie.load(params[:imdb_id])
  erb :movie
end

get '/add' do
  response.headers['Cache-Control'] = 'public, max-age=31556926'
  erb :add
end

post '/create' do
  movie = Movie.add!(params[:imdb_id])
  redirect_url = movie ? "/movie/#{params[:imdb_id]}" : "/add"
  redirect redirect_url
end
