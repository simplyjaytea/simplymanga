// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'anime_engine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$EngineAction {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineAction);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'EngineAction()';
}


}

/// @nodoc
class $EngineActionCopyWith<$Res>  {
$EngineActionCopyWith(EngineAction _, $Res Function(EngineAction) __);
}


/// Adds pattern-matching-related methods to [EngineAction].
extension EngineActionPatterns on EngineAction {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( EngineAction_Play value)?  play,TResult Function( EngineAction_AwaitChallenge value)?  awaitChallenge,TResult Function( EngineAction_Retry value)?  retry,TResult Function( EngineAction_Fail value)?  fail,TResult Function( EngineAction_Idle value)?  idle,required TResult orElse(),}){
final _that = this;
switch (_that) {
case EngineAction_Play() when play != null:
return play(_that);case EngineAction_AwaitChallenge() when awaitChallenge != null:
return awaitChallenge(_that);case EngineAction_Retry() when retry != null:
return retry(_that);case EngineAction_Fail() when fail != null:
return fail(_that);case EngineAction_Idle() when idle != null:
return idle(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( EngineAction_Play value)  play,required TResult Function( EngineAction_AwaitChallenge value)  awaitChallenge,required TResult Function( EngineAction_Retry value)  retry,required TResult Function( EngineAction_Fail value)  fail,required TResult Function( EngineAction_Idle value)  idle,}){
final _that = this;
switch (_that) {
case EngineAction_Play():
return play(_that);case EngineAction_AwaitChallenge():
return awaitChallenge(_that);case EngineAction_Retry():
return retry(_that);case EngineAction_Fail():
return fail(_that);case EngineAction_Idle():
return idle(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( EngineAction_Play value)?  play,TResult? Function( EngineAction_AwaitChallenge value)?  awaitChallenge,TResult? Function( EngineAction_Retry value)?  retry,TResult? Function( EngineAction_Fail value)?  fail,TResult? Function( EngineAction_Idle value)?  idle,}){
final _that = this;
switch (_that) {
case EngineAction_Play() when play != null:
return play(_that);case EngineAction_AwaitChallenge() when awaitChallenge != null:
return awaitChallenge(_that);case EngineAction_Retry() when retry != null:
return retry(_that);case EngineAction_Fail() when fail != null:
return fail(_that);case EngineAction_Idle() when idle != null:
return idle(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String server)?  play,TResult Function( String server)?  awaitChallenge,TResult Function( String server)?  retry,TResult Function( String reason)?  fail,TResult Function()?  idle,required TResult orElse(),}) {final _that = this;
switch (_that) {
case EngineAction_Play() when play != null:
return play(_that.server);case EngineAction_AwaitChallenge() when awaitChallenge != null:
return awaitChallenge(_that.server);case EngineAction_Retry() when retry != null:
return retry(_that.server);case EngineAction_Fail() when fail != null:
return fail(_that.reason);case EngineAction_Idle() when idle != null:
return idle();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String server)  play,required TResult Function( String server)  awaitChallenge,required TResult Function( String server)  retry,required TResult Function( String reason)  fail,required TResult Function()  idle,}) {final _that = this;
switch (_that) {
case EngineAction_Play():
return play(_that.server);case EngineAction_AwaitChallenge():
return awaitChallenge(_that.server);case EngineAction_Retry():
return retry(_that.server);case EngineAction_Fail():
return fail(_that.reason);case EngineAction_Idle():
return idle();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String server)?  play,TResult? Function( String server)?  awaitChallenge,TResult? Function( String server)?  retry,TResult? Function( String reason)?  fail,TResult? Function()?  idle,}) {final _that = this;
switch (_that) {
case EngineAction_Play() when play != null:
return play(_that.server);case EngineAction_AwaitChallenge() when awaitChallenge != null:
return awaitChallenge(_that.server);case EngineAction_Retry() when retry != null:
return retry(_that.server);case EngineAction_Fail() when fail != null:
return fail(_that.reason);case EngineAction_Idle() when idle != null:
return idle();case _:
  return null;

}
}

}

/// @nodoc


class EngineAction_Play extends EngineAction {
  const EngineAction_Play({required this.server}): super._();
  

 final  String server;

/// Create a copy of EngineAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineAction_PlayCopyWith<EngineAction_Play> get copyWith => _$EngineAction_PlayCopyWithImpl<EngineAction_Play>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineAction_Play&&(identical(other.server, server) || other.server == server));
}


@override
int get hashCode {
    return Object.hash(runtimeType,server);
}

@override
String toString() {
    return 'EngineAction.play(server: $server)';
}


}

/// @nodoc
abstract mixin class $EngineAction_PlayCopyWith<$Res> implements $EngineActionCopyWith<$Res> {
  factory $EngineAction_PlayCopyWith(EngineAction_Play value, $Res Function(EngineAction_Play) _then) = _$EngineAction_PlayCopyWithImpl;
@useResult
$Res call({
 String server
});




}
/// @nodoc
class _$EngineAction_PlayCopyWithImpl<$Res>
    implements $EngineAction_PlayCopyWith<$Res> {
  _$EngineAction_PlayCopyWithImpl(this._self, this._then);

  final EngineAction_Play _self;
  final $Res Function(EngineAction_Play) _then;

/// Create a copy of EngineAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? server = null,}) {
  return _then(EngineAction_Play(
server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EngineAction_AwaitChallenge extends EngineAction {
  const EngineAction_AwaitChallenge({required this.server}): super._();
  

 final  String server;

/// Create a copy of EngineAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineAction_AwaitChallengeCopyWith<EngineAction_AwaitChallenge> get copyWith => _$EngineAction_AwaitChallengeCopyWithImpl<EngineAction_AwaitChallenge>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineAction_AwaitChallenge&&(identical(other.server, server) || other.server == server));
}


@override
int get hashCode {
    return Object.hash(runtimeType,server);
}

@override
String toString() {
    return 'EngineAction.awaitChallenge(server: $server)';
}


}

/// @nodoc
abstract mixin class $EngineAction_AwaitChallengeCopyWith<$Res> implements $EngineActionCopyWith<$Res> {
  factory $EngineAction_AwaitChallengeCopyWith(EngineAction_AwaitChallenge value, $Res Function(EngineAction_AwaitChallenge) _then) = _$EngineAction_AwaitChallengeCopyWithImpl;
@useResult
$Res call({
 String server
});




}
/// @nodoc
class _$EngineAction_AwaitChallengeCopyWithImpl<$Res>
    implements $EngineAction_AwaitChallengeCopyWith<$Res> {
  _$EngineAction_AwaitChallengeCopyWithImpl(this._self, this._then);

  final EngineAction_AwaitChallenge _self;
  final $Res Function(EngineAction_AwaitChallenge) _then;

/// Create a copy of EngineAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? server = null,}) {
  return _then(EngineAction_AwaitChallenge(
server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EngineAction_Retry extends EngineAction {
  const EngineAction_Retry({required this.server}): super._();
  

 final  String server;

/// Create a copy of EngineAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineAction_RetryCopyWith<EngineAction_Retry> get copyWith => _$EngineAction_RetryCopyWithImpl<EngineAction_Retry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineAction_Retry&&(identical(other.server, server) || other.server == server));
}


@override
int get hashCode {
    return Object.hash(runtimeType,server);
}

@override
String toString() {
    return 'EngineAction.retry(server: $server)';
}


}

/// @nodoc
abstract mixin class $EngineAction_RetryCopyWith<$Res> implements $EngineActionCopyWith<$Res> {
  factory $EngineAction_RetryCopyWith(EngineAction_Retry value, $Res Function(EngineAction_Retry) _then) = _$EngineAction_RetryCopyWithImpl;
@useResult
$Res call({
 String server
});




}
/// @nodoc
class _$EngineAction_RetryCopyWithImpl<$Res>
    implements $EngineAction_RetryCopyWith<$Res> {
  _$EngineAction_RetryCopyWithImpl(this._self, this._then);

  final EngineAction_Retry _self;
  final $Res Function(EngineAction_Retry) _then;

/// Create a copy of EngineAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? server = null,}) {
  return _then(EngineAction_Retry(
server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EngineAction_Fail extends EngineAction {
  const EngineAction_Fail({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of EngineAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineAction_FailCopyWith<EngineAction_Fail> get copyWith => _$EngineAction_FailCopyWithImpl<EngineAction_Fail>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineAction_Fail&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'EngineAction.fail(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $EngineAction_FailCopyWith<$Res> implements $EngineActionCopyWith<$Res> {
  factory $EngineAction_FailCopyWith(EngineAction_Fail value, $Res Function(EngineAction_Fail) _then) = _$EngineAction_FailCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$EngineAction_FailCopyWithImpl<$Res>
    implements $EngineAction_FailCopyWith<$Res> {
  _$EngineAction_FailCopyWithImpl(this._self, this._then);

  final EngineAction_Fail _self;
  final $Res Function(EngineAction_Fail) _then;

/// Create a copy of EngineAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(EngineAction_Fail(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EngineAction_Idle extends EngineAction {
  const EngineAction_Idle(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineAction_Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'EngineAction.idle()';
}


}




// dart format on
