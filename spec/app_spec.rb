require_relative 'spec_helper'

RSpec.describe 'Learn Ruby API' do
  it 'returns pong on /ping' do
    get '/ping'
    expect(last_response.status).to eq 200
    expect(last_response.body).to eq 'pong'
  end

  it 'returns healthy for /healthz' do
    get '/healthz'
    expect(last_response.status).to eq 200
    json = JSON.parse(last_response.body)
    expect(json['success']).to be true
    expect(json['data']['status']).to eq 'healthy'
  end

  it 'returns version on /version' do
    get '/version'
    expect(last_response.status).to eq 200
    json = JSON.parse(last_response.body)
    expect(json['success']).to be true
    expect(json['data']['name']).to eq 'learn-ruby'
  end

  it 'echoes posted JSON on /echo' do
    headers = { 'CONTENT_TYPE' => 'application/json' }
    payload = { 'msg' => 'hello' }
    post '/echo', payload.to_json, headers
    expect(last_response.status).to eq 200
    json = JSON.parse(last_response.body)
    expect(json['success']).to be true
    expect(json['data']['echo']['msg']).to eq 'hello'
  end
end
