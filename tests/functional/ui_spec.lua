---@diagnostic disable: undefined-field, redefined-local
local GLOBALS = require("kulala.globals")
local CONFIG = require("kulala.config")
local DB = require("kulala.db")
local kulala = require("kulala")

local kulala_name = GLOBALS.UI_ID
local kulala_config = CONFIG.options

local h = require("test_helper")

describe("UI", function()
  local curl, system, wait_for_requests
  local input, notify, dynamic_vars
  local lines, result, expected, http_buf, ui_buf

  before_each(function()
    h.delete_all_bufs()

    input = h.Input.stub()
    notify = h.Notify.stub()
    dynamic_vars = h.Dynamic_vars.stub()

    curl = h.Curl.stub({
      ["*"] = {
        stats = h.load_fixture("fixtures/stats.json"),
      },
      ["http://localhost:3001/request_1"] = {
        headers = h.load_fixture("fixtures/request_1_headers.txt"),
        body = h.load_fixture("fixtures/request_1_body.txt"),
        errors = h.load_fixture("fixtures/request_1_errors.txt"),
      },
      ["http://localhost:3001/request_2"] = {
        headers = h.load_fixture("fixtures/request_2_headers.txt"),
        body = h.load_fixture("fixtures/request_2_body.txt"),
        errors = h.load_fixture("fixtures/request_2_errors.txt"),
      },
    })

    system = h.System.stub({ "curl" }, {
      on_call = function(system)
        curl.request(system)
      end,
    })

    wait_for_requests = function(requests_no)
      system:wait(3000, function()
        ui_buf = vim.fn.bufnr(kulala_name)
        return curl.requests_no >= requests_no and ui_buf > 0
      end)
    end

    kulala_config = CONFIG.setup({
      global_keymaps = true,
      default_view = "body",
      display_mode = "float",
    })

    lines = h.to_table(
      [[
        GET http://localhost:3001/request_1

        ###

        GET http://localhost:3001/request_2
      ]],
      true
    )

    http_buf = h.create_buf(lines, "test.http")
  end)

  after_each(function()
    h.delete_all_bufs()
    curl.reset()
    system.reset()
    input.reset()
    notify.reset()
    dynamic_vars.reset()
  end)

  describe("show output of requests", function()
    it("in headers mode", function()
      kulala_config.default_view = "headers"

      kulala.run()
      wait_for_requests(1)

      result = h.get_buf_lines(ui_buf):to_string()
      expected = h.load_fixture("fixtures/request_1_headers.txt")

      assert.is_same(expected, result)
    end)

    it("in body mode", function()
      kulala.run()
      wait_for_requests(1)

      result = h.get_buf_lines(ui_buf):to_string()
      expected = h.load_fixture("fixtures/request_1_body.txt")

      assert.is_same(expected, result)
    end)

    it("for current line in body mode", function()
      vim.fn.setpos(".", { 0, 5, 0, 0 })
      kulala.run()
      wait_for_requests(1)

      result = h.get_buf_lines(ui_buf):to_string()
      expected = h.load_fixture("fixtures/request_2_body.txt")

      assert.is_same(expected, result)
    end)

    it("for current line in in non-http buffer and strips comments chars", function()
      curl.stub({
        ["https://httpbin.org/advanced_1"] = {
          body = h.load_fixture("fixtures/advanced_A_1_body.txt"),
        },
      })

      h.create_buf(
        ([[
          -- @foobar=bar
          ;; @ENV_PROJECT = project_name
          
          #- POST https://httpbin.org/advanced_1 HTTP/1.1
          /*-- Content-Type: application/json
        ]]):to_table(),
        "test.lua"
      )

      h.send_keys("3j")
      kulala.run()
      wait_for_requests(1)

      local cmd = DB.data.current_request.cmd
      assert.is_same("https://httpbin.org/advanced_1", cmd[#cmd])
    end)

    it("for current selection in in non-http buffer", function()
      curl.stub({
        ["https://httpbin.org/advanced_1"] = {
          body = h.load_fixture("fixtures/advanced_A_1_body.txt"),
        },
      })

      h.create_buf(
        ([[
          Some text
          Some text

        //###

          -- @foobar=bar
          ##@ENV_PROJECT = project_name

          ;# @accept chunked
          /* POST https://httpbin.org/advanced_1 HTTP/1.1
          #  Content-Type: application/json

        // {
        (*   "project": "{{ENV_PROJECT}}",
        ;;     "results": [
             {
        ;;       "id": 1,
        ;;       "desc": "{{foobar}}"
             },
             ]
        ;; }
          > {%
          client.log("TEST LOG")
          %}
        ]]):to_table(true),
        "test.lua"
      )

      h.send_keys("3jV20j")

      kulala.run()
      wait_for_requests(1)

      local cmd = DB.data.current_request.cmd
      assert.is_same("https://httpbin.org/advanced_1", cmd[#cmd])

      local computed_body = DB.data.current_request.body_computed
      local expected_computed_body = '{\n"project": "project_name",\n"results": [\n{\n"id": 1,\n"desc": "bar"\n},\n]\n}'

      assert.is_same(expected_computed_body, computed_body)
      assert.has_string(notify.messages, "TEST LOG")
    end)

    it("last request in body_headers mode for run_all", function()
      kulala_config.default_view = "headers_body"

      kulala.run_all()
      wait_for_requests(2)

      expected = h.load_fixture("fixtures/request_2_headers_body.txt")
      result = h.get_buf_lines(ui_buf):to_string()

      assert.is_same(2, curl.requests_no)
      assert.is_same(expected, result)
    end)

    it("in verbose mode", function()
      kulala_config.default_view = "verbose"

      kulala.run()
      wait_for_requests(1)

      result = h.get_buf_lines(ui_buf):to_string()
      expected = h.load_fixture("fixtures/request_1_verbose.txt")

      assert.is_same(expected, result)
    end)

    it("in verbose mode for run_all", function()
      kulala_config.default_view = "verbose"

      kulala.run_all()
      wait_for_requests(2)

      expected = h.load_fixture("fixtures/request_2_verbose.txt")
      result = h.get_buf_lines(ui_buf):to_string()

      assert.is_same(2, curl.requests_no)
      assert.is_same(expected, result)
    end)

    it("stats of the request", function()
      kulala_config.default_view = "stats"

      kulala.run()
      wait_for_requests(1)

      expected = h.load_fixture("fixtures/request_1_stats.txt")
      result = h.get_buf_lines(ui_buf):to_string()

      assert.is_same(expected, result)
    end)

    it("in script mode", function()
      kulala_config.default_view = "script_output"

      h.set_buf_lines(
        http_buf,
        ([[
          GET http://localhost:3001/request_1

          > {%
          client.log(response.headers.valuesOf("Date").value);
          client.log("JS: TEST");
          %}
      ]]):to_table(true)
      )

      kulala.run()
      wait_for_requests(1)

      expected = h.load_fixture("fixtures/request_1_script.txt")
      result = h.get_buf_lines(ui_buf):to_string()

      assert.is_same(expected, result)
    end)

    it("replays last request", function()
      kulala.run()
      wait_for_requests(1)

      h.delete_all_bufs()

      kulala.replay()
      wait_for_requests(2)

      result = h.get_buf_lines(ui_buf):to_string()
      expected = h.load_fixture("fixtures/request_1_body.txt")

      assert.is_same(expected, result)
    end)
  end)

  describe("UI features", function()
    it("opens results in split", function()
      kulala_config.display_mode = "split"

      kulala.run()
      wait_for_requests(1)

      local win_config = vim.api.nvim_win_get_config(vim.fn.bufwinid(ui_buf))
      assert.is_same("right", win_config.split)
    end)

    it("opens results in float", function()
      kulala.run()
      wait_for_requests(1)

      local win_config = vim.api.nvim_win_get_config(vim.fn.bufwinid(ui_buf))
      assert.is_same("editor", win_config.relative)
    end)

    it("closes float and deletes buffer on 'q'", function()
      kulala_config.q_to_close_float = true

      kulala.run()
      wait_for_requests(1)

      h.send_keys("q")
      assert.is_false(vim.fn.bufexists(ui_buf) > 0)
    end)

    it("closes ui and current buffer if it is *.http|rest", function()
      kulala_config.q_to_close_float = true

      kulala.run()
      wait_for_requests(1)
      kulala.close()

      assert.is_false(vim.fn.bufexists(http_buf) > 0)
      assert.is_false(vim.fn.bufexists(ui_buf) > 0)
    end)

    it("shows inspect window", function()
      h.set_buf_lines(
        http_buf,
        ([[
          @foobar=bar
          @ENV_PROJECT = project_name

          POST https://httpbin.org/post HTTP/1.1
          Content-Type: application/json

          {
            "project": "{{ENV_PROJECT}}",
              "results": [
              {
                "id": 1,
                "desc": "{{foobar}}"
              },
              ]
          }]]):to_table(true)
      )

      kulala.inspect()
      ui_buf = vim.fn.bufnr("kulala://inspect")

      expected = ([[
        POST https://httpbin.org/post HTTP/1.1
        Content-Type: application/json

        {
          "project": "project_name",
            "results": [
            {
              "id": 1,
              "desc": "bar"
            },
            ]
        }]]):to_string(true)

      result = h.get_buf_lines(ui_buf):to_string()
      assert.is_same(expected, result)
    end)

    it("pastes curl command", function()
      vim.fn.setreg(
        "+",
        [[curl -X 'POST' -v -s --data '{ "foo": "bar" }' -H 'Content-Type:application/json' --http1.1 -A 'kulala.nvim/4.10.0' 'https://httpbin.org/post']]
      )
      h.set_buf_lines(http_buf, {})

      kulala.from_curl()

      expected = ([[
          # curl -X 'POST' -v -s --data '{ "foo": "bar" }' -H 'Content-Type:application/json' --http1.1 -A 'kulala.nvim/4.10.0' 'https://httpbin.org/post'
          POST https://httpbin.org/post HTTP/1.1
          content-type: application/json
          user-agent: kulala.nvim/%s

          { "foo": "bar" }
        ]]):format(GLOBALS.VERSION):to_string(true)

      result = h.get_buf_lines(http_buf):to_string()
      assert.are.same(expected, result)
    end)

    it("copies curl command with body", function()
      h.create_buf(
        ([[
        POST http://localhost:3001/request_1
        Content-Type: application/json

        {
          "foo": "bar"
        }
      ]]):to_table(true),
        "test.rest"
      )

      kulala.copy()

      expected = ([[curl -X 'POST' -v -s -H 'Content-Type:application/json' --data-binary "{"foo": "bar"}" -A 'kulala.nvim/%s' 'http://localhost:3001/request_1']]):format(
        GLOBALS.VERSION
      )
      result = vim.fn.getreg("+")
      assert.are.same(expected, result)
    end)
  end)
end)
