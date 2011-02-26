require 'sinatra'
require 'httparty'
require 'active_record'
require 'indextank'
include ERB::Util # Make url encode methods available

class Search
  
  def self.attributes 
    [:year, :name, :imdb_id, :genre, :all, :duration]
  end
  
  self.attributes.each do |attribute|
    attr_accessor attribute
  end
  
  def initialize(attrs = {})
    self.class.attributes.each do |attribute|
      self.send("#{attribute}=", (attrs[attribute.to_s] rescue nil))
    end
  end
  
  def conditions
    conditions = []
    conditions << "year:#{year}" if year.present?
    conditions << "name:#{name}" if name.present?
    conditions << "imdb_id:#{imdb_id}" if imdb_id.present?
    conditions << "genres:#{genre}" if genre.present?
    conditions = ["all:true"] if all.present? || conditions.empty?
    conditions.join(" ")
  end
  
  def variables
    duration.present? ? {:docvar_filters => {0 => [[0,duration]]}} : {}
  end
  
  # Search for movies in the Index Tank store and
  # returns them as an array of movie instances
  def results
    documents = [conditions, variables].any?(&:present?) ? IndexTankClient.new.search(conditions, variables) : []
    movie_results = documents.inject([]) do |movies, document|
      movies << Movie.convert_from_index_tank(document)
    end
    movie_results.sort_by(&:name)
  end
  
end


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
    @index.document(movie.tmdb_id).add(attrs, :variables => {0 => movie.duration})
  end
  
  def search(conditions, variables = nil)
    @index.search(conditions, {:fetch => Movie.new.attributes.keys.join(","), :len => 999}.merge!(variables) )["results"]
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
    movie.overview = attrs["overview"] || ""
    movie.language = attrs["language"] || ""
    movie.cover_url = (attrs["images"]["image"].select{ |img| img["size"] == "cover"  }.first["url"] || "" rescue "")
    movie.thumb_url = (attrs["images"]["image"].select{ |img| img["size"] == "thumb"  }.first["url"] || "" rescue "")
    movie.year = Time.parse(attrs["released"]).year rescue ""
    movie.tmdb_id = attrs["id"]
    movie.imdb_id = attrs["imdb_id"]
    movie.duration = attrs["runtime"] || "" rescue ""
    movie.certification = attrs["certification"] || "" rescue ""
    movie.genres = attrs["categories"]["category"].map{ |c| c["name"] }.sort.join(", ") rescue ""
    movie
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
    ["Action", "Adventure", "Animation", "Comedy", "Crime", "Disaster", "Documentary", "Drama", "Eastern", "Family", "Fantasy", "History", "Holiday", "Horror", "Musical", "Mystery", "Romance", "Science Fiction", "Thriller", "War", "Western"].sort
  end
  
  def self.durations
    {
      60 => "1 hour",
      70 => "1 hour 10 minutes",
      80 => "1 hour 20 minutes",
      90 => "1 hour 30 minutes",
      100 => "1 hour 40 minutes",
      110 => "1 hour 50 minutes",
      120 => "2 hours",
      130 => "2 hours 10 minutes",
      140 => "2 hours 20 minutes",
      150 => "2 hours 30 minutes"
    }
  end
  
end

get '/' do
  #response.headers['Cache-Control'] = 'public, max-age=31556926'
  load_search
  redirect "/movie/#{@movies.first.imdb_id}" if @movies.length == 1
  erb :index
end

get '/movie/:imdb_id' do
  response.headers['Cache-Control'] = 'public, max-age=31556926'
  load_search
  @movie = Search.new("imdb_id" => params[:imdb_id]).results.first
  erb :movie
end

get '/add' do
  response.headers['Cache-Control'] = 'public, max-age=31556926'
  load_search
  erb :add
end

post '/create' do
  movie = Movie.add!(params[:imdb_id])
  redirect_url = movie ? "/movie/#{params[:imdb_id]}" : "/add"
  redirect redirect_url
end

def load_search
  @genres = Movie.genres
  @durations = Movie.durations
  @search = Search.new(params[:search] || {"all" => true})
  
  @movies = @search.results
end
