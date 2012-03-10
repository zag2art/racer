{expect, calls} = require '../util'
{transaction} = require '../../src/racer'
{mockSocketModel, BrowserModel: Model} = require '../util/model'

describe 'Model.ref', ->

  it 'should support getting', ->
    model = new Model
    model.set 'info',
      numbers:
        first: 2
        second: 10
    model.set 'numKey', 'first'
    model.ref '_numbers', 'info.numbers'
    model.ref '_number', '_numbers', 'numKey'

    # Test non-keyed object reference
    expect(model.get '_numbers').to.specEql first: 2, second: 10
    # Test property below object reference
    expect(model.get '_numbers.second').to.eql 10
    # Test keyed object reference
    expect(model.get '_number').to.eql 2

    # Test changing key object reference with speculative set
    model.set 'numKey', 'second'
    expect(model.get '_number').to.eql 10
    # Test changing referenced object wtih speculative set
    model.set 'info', numbers: {first: 3, second: 7}
    expect(model.get '_number').to.eql 7

  it 'should support setting', ->
    model = new Model

    model.ref '_color', 'colors', 'selected'
    ref = model._getRef '_color'
    expect(model.get()).to.specEql
      _color: ref

    # Set a key value
    model.set 'selected', 'blue'
    expect(model.get()).to.specEql
      _color: ref
      selected: 'blue'

    # Setting a property on a reference should update the referenced object
    model.set '_color.hex', '#0f0'
    expect(model.get()).to.specEql
      colors:
        blue:
          hex: '#0f0'
      _color: ref
      selected: 'blue'

    # Creating a ref on a path that is currently a reference should modify
    # the reference, similar to setting an object reference in Javascript
    model.ref '_color', 'colors.blue'
    ref2 = model._getRef '_color'
    expect(model.get()).to.specEql
      colors:
        blue:
          hex: '#0f0'
      _color: ref2
      selected: 'blue'

    # Test setting on a non-keyed reference
    model.set '_color.compliment', 'yellow'
    expect(model.get()).to.specEql
      colors:
        blue:
          hex: '#0f0'
          compliment: 'yellow'
      _color: ref2
      selected: 'blue'

  it 'should support getting nested references', ->
    model = new Model
    model.set 'users.1', 'brian'
    model.ref '_session.user', 'users.1'
    expect(model.get '_session.user').to.equal 'brian'

    model.set 'userId', '1'
    model.ref '_session.user', 'users', 'userId'
    expect(model.get '_session.user').to.equal 'brian'

    model.set '_session', userId: 1
    model.ref '_session.user', 'users', '_session.userId'
    expect(model.get '_session.user').to.equal 'brian'

  it 'should support getting and setting a reference to an undefined path', ->
    model = new Model

    model.ref '_color', 'green'
    expect(model.get '_color').to.equal undefined
    expect(model.get '_color.hex').to.equal undefined

    model.set '_color.hex', '#0f0'
    expect(model.get 'green').to.specEql hex: '#0f0'

    model.del '_color.hex'
    expect(model.get 'green').to.specEql {}

    model.del 'green'
    expect(model.get 'green').to.equal undefined

  it 'should support push', ->
    model = new Model
    model.ref '_items', 'arr'
    model.push '_items', 'item'
    expect(model.get 'arr').to.specEql ['item']

  it 'adds a model._getRef method', ->
    model = new Model
    model.ref '_firstNumber', 'numbers.first'
    expect(model.get '_firstNumber').to.equal undefined
    expect(model._getRef '_firstNumber').to.be.a 'function'

  it 'does not have an effect after being deleted', ->
    model = new Model
    model.ref '_color', 'colors.green'
    ref = model._getRef '_color'
    model.set '_color.hex', '#0f0'
    expect(model.get()).to.specEql
      colors:
        green:
          hex: '#0f0'
      _color: ref

    model = new Model
    model.ref '_color', 'colors.green'
    model.del '_color'
    expect(model.get()).to.specEql {}
    model.set '_color.hex', '#0f0'
    expect(model.get()).to.specEql
      _color:
        hex: '#0f0'

  it 'should dereference paths', calls 1, (done) ->
    count = 0
    [model, sockets] = mockSocketModel '0', 'txn', (txn) ->
      expect(txn.slice()).to.eql expected[count++]
      sockets._disconnect()
      done()
    ref = model.ref '_color', 'colors.green'
    expected = [transaction.create(
      base: 0, id: '0.1', method: 'set', args: ['colors.green.hex', '#0f0']
    )]
    model.set '_color.hex', '#0f0'

  it 'should emit on both paths when setting under reference', calls 2, (done) ->
    model = new Model
    model.ref '_color', 'colors.green'
    model.on 'set', 'colors.green.*', cb = (prop, value, previous, isLocal) ->
      expect(prop).to.equal 'hex'
      expect(value).to.equal '#0f0'
      expect(previous).to.equal undefined
      expect(isLocal).to.equal true
      done()
    model.on 'set', '_color.*', cb
    model.set '_color.hex', '#0f0'

  it 'should emit on both paths when setting under referenced path', calls 2, (done) ->
    model = new Model
    model.ref '_color', 'colors.green'
    model.on 'set', 'colors.green.*', cb = (prop, value, previous, isLocal) ->
      expect(prop).to.equal 'hex'
      expect(value).to.equal '#0f0'
      expect(previous).to.equal undefined
      expect(isLocal).to.equal true
      done()
    model.on 'set', '_color.*', cb
    model.set 'colors.green.hex', '#0f0'

  it 'should emit on both paths when setting to referenced path', calls 2, (done) ->
    model = new Model
    model.ref '_color', 'colors.green'
    model.on 'set', 'colors.green', cb = (value, previous, isLocal) ->
      expect(value).to.eql hex: '#0f0'
      expect(previous).to.equal undefined
      expect(isLocal).to.equal true
      done()
    model.on 'set', '_color', cb
    model.set 'colors.green', hex: '#0f0'

  it 'should not emit under referenced path after reference is deleted', calls 0, (done) ->
    model = new Model
    model.ref '_color', 'colors.green'
    model.del '_color'
    model.on 'set', 'colors.green.*', done
    model.set '_color.hex', '#0f0'

  it 'should not emit under reference after reference is deleted', calls 0, (done) ->
    model = new Model
    model.ref '_color', 'colors.green'
    model.del '_color'
    model.on 'set', '_color.*', done
    model.set 'colors.green.hex', '#0f0'

  it 'should emit upstream on a reference to a reference', calls 2, (done) ->
    model = new Model
    model.ref '_color', 'colors._green'
    model.ref 'colors._green', 'bestColor'
    model.on 'set', '_color.hex', (value) ->
      expect(value).to.eql '#0f0'
      done()
    model.on 'set', 'colors.*', (path, value) ->
      expect(path).to.eql '_green.hex'
      expect(value).to.eql '#0f0'
      done()
    model.set 'bestColor.hex', '#0f0'

  it 'should emit upstream on a reference to a reference alternate', calls 3, (done) ->
    model = new Model
    model.ref '_room', 'rooms.lobby'
    model.ref '_user', '_room.users.0'
    model.on 'set', '_room.users.0.name', cb = (value) ->
      expect(value).to.eql '#0f0'
      done()
    model.on 'set', '_user.name', cb
    model.on 'set', 'rooms.lobby.users.0.name', cb
    model.set '_user.name', '#0f0'

  it 'should raise an event for each reference to the same path', calls 2, (done) ->
    model = new Model
    model.ref '_color', 'colors.green'
    model.ref '_bestColor', 'colors.green'
    model.on 'set', '_color', done
    model.on 'set', '_bestColor', done
    model.set 'colors.green', {}

  it 'should work on different parts of a nested path', calls 2, (done) ->
    model = new Model
    model.ref '_a', 'w.x.y.z'
    model.ref '_b', 'w.x'
    model.on 'set', '_a', (value) ->
      expect(value).to.eql 'green'
      done()
    model.on 'set', '_b.*', (path, value) ->
      expect(path).to.eql 'y.z'
      expect(value).to.eql 'green'
      done()
    model.set 'w.x.y.z', 'green'

  it 'should emit on both paths when setting under reference with key', calls 2, (done) ->
    model = new Model
    model.set 'colorName', 'green'
    model.ref '_color', 'colors', 'colorName'
    model.on 'set', 'colors.green.*', cb = (prop, value, previous, isLocal) ->
      expect(prop).to.equal 'hex'
      expect(value).to.equal '#0f0'
      expect(previous).to.equal undefined
      expect(isLocal).to.equal true
      done()
    model.on 'set', '_color.*', cb
    model.set '_color.hex', '#0f0'

  it 'should emit on both paths when setting under referenced path with key', calls 2, (done) ->
    model = new Model
    model.set 'colorName', 'green'
    model.ref '_color', 'colors', 'colorName'
    model.on 'set', 'colors.green.*', cb = (prop, value, previous, isLocal) ->
      expect(prop).to.equal 'hex'
      expect(value).to.equal '#0f0'
      expect(previous).to.equal undefined
      expect(isLocal).to.equal true
      done()
    model.on 'set', '_color.*', cb
    model.set 'colors.green.hex', '#0f0'

  it 'should emit on both paths when setting to referenced path with key', calls 2, (done) ->
    model = new Model
    model.set 'colorName', 'green'
    model.ref '_color', 'colors', 'colorName'
    model.on 'set', 'colors.green', cb = (value, previous, isLocal) ->
      expect(value).to.eql hex: '#0f0'
      expect(previous).to.equal undefined
      expect(isLocal).to.equal true
      done()
    model.on 'set', '_color', cb
    model.set 'colors.green', hex: '#0f0'

  it 'should not emit when setting under non-matching key', calls 1, (done) ->
    model = new Model
    model.set 'colorName', 'green'
    model.ref '_color', 'colors', 'colorName'
    model.on 'set', '*', done
    model.set 'colors.cream.hex', '#0f0'

  it 'should not emit when setting to non-matching key', calls 1, (done) ->
    model = new Model
    model.set 'colorName', 'green'
    model.ref '_color', 'colors', 'colorName'
    model.on 'set', '*', done
    model.set 'colors.cream', hex: '#0f0'

  it 'should emit events with a nested key', calls 2, (done) ->
    model = new Model
    model.set 'users.1', name: 'brian'
    model.set 'userId', '1'
    model.ref '_session.user', 'users', 'userId'
    model.on 'set', '_session.user.name', done
    model.on 'set', 'users.1.name', done
    model.set '_session.user.name', 'nate'

  it 'should emit events with a self-referencing key', calls 3, (done) ->
    model = new Model
    model.ref '_room', 'rooms.1'
    model.set '_session.userId', 0
    model.ref '_session.user', '_room.users', '_session.userId'
    model.on 'set', 'rooms.1.users.0.name', cb = (value) ->
      expect(value).to.eql 'Bob'
      done()
    model.on 'set', '_room.users.0.name', cb
    model.on 'set', '_session.user.name', cb
    model.set '_session.user.name', 'Bob'

  it 'should emit once after setting a reference twice on the same path', calls 1, (done) ->
    model = new Model
    model.ref '_color', 'colors.green'
    model.ref '_color', 'colors.green'
    model.on 'set', '_color.*', done
    model.set 'colors.green.hex', '#0f0'

  it 'supports specifying from path via scoped model', ->
    model = new Model
    color = model.at '_color'
    color.at('favorite').ref 'green'
    ref = model._getRef '_color.favorite'
    color.set 'favorite.hex', '#0f0'
    expect(color.get 'favorite').to.specEql hex: '#0f0'
    expect(model.get()).to.specEql
      _color:
        favorite: ref
      green:
        hex: '#0f0'

  it 'supports a scoped model as the from argument', ->
    model = new Model
    favoriteColor = model.at('_color').at('favorite')
    model.ref favoriteColor, 'green'
    ref = model._getRef '_color.favorite'
    favoriteColor.set 'hex', '#0f0'
    expect(favoriteColor.get()).to.specEql hex: '#0f0'
    expect(model.get()).to.specEql
      _color:
        favorite: ref
      green:
        hex: '#0f0'

  it 'supports a scoped model as the to argument', ->
    model = new Model
    color = model.at('green')
    model.ref '_color.favorite', color
    ref = model._getRef '_color.favorite'
    model.set '_color.favorite.hex', '#0f0'
    expect(model.get '_color.favorite').to.specEql hex: '#0f0'
    expect(model.get()).to.specEql
      _color:
        favorite: ref
      green:
        hex: '#0f0'

  it 'supports a scoped model as the from and to argument', ->
    model = new Model
    color = model.at('green')
    favoriteColor = model.at('_color').at('favorite')
    model.ref favoriteColor, color
    ref = model._getRef '_color.favorite'
    favoriteColor.set 'hex', '#0f0'
    expect(favoriteColor.get()).to.specEql hex: '#0f0'
    expect(model.get()).to.specEql
      _color:
        favorite: ref
      green:
        hex: '#0f0'

  it 'returns a scoped model for the from argument', ->
    model = new Model
    color = model.ref '_color', 'colors.green'
    expect(color.path()).to.equal '_color'
    color.set 'hex', '#0f0'
    expect(color.get 'hex').to.equal '#0f0'
    expect(model.get 'colors.green').to.specEql hex: '#0f0'
