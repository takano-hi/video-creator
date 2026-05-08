require "net/http"
require "json"

class McpController < ApplicationController
  VOICEVOX_BASE = "http://localhost:50021"

  TOOLS = [
    {
      name: "get_speakers",
      description: "VOICEVOX で利用可能なスピーカー（声優）の一覧をスタイルIDとともに返す",
      inputSchema: { type: "object", properties: {}, required: [] }
    }
  ].freeze

  def handle
    body = JSON.parse(request.body.read)
    id = body["id"]

    return head :accepted if id.nil?

    result = route_rpc(body["method"], body["params"] || {})
    render json: { jsonrpc: "2.0", id: id, result: result }
  rescue => e
    render json: { jsonrpc: "2.0", id: body&.dig("id"), error: { code: -32603, message: e.message } }
  end

  private

  def route_rpc(method, params)
    case method
    when "initialize"
      {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "voicevox-mcp", version: "1.0" }
      }
    when "tools/list"
      { tools: TOOLS }
    when "tools/call"
      call_tool(params["name"], params["arguments"] || {})
    else
      raise "Method not found: #{method}"
    end
  end

  def call_tool(name, _args)
    case name
    when "get_speakers"
      speakers = voicevox_get("/speakers")
      { content: [ { type: "text", text: JSON.pretty_generate(speakers) } ] }
    else
      raise "Unknown tool: #{name}"
    end
  end

  def voicevox_get(path)
    uri = URI("#{VOICEVOX_BASE}#{path}")
    response = Net::HTTP.get_response(uri)
    JSON.parse(response.body)
  end
end
