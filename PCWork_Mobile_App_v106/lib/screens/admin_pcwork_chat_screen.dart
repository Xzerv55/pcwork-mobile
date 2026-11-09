import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AdminPCWorkChatScreen extends StatefulWidget {
  const AdminPCWorkChatScreen({super.key, required this.api, required this.tokenProvider, required this.sessionKey, required this.english, required this.isDarkTheme, required this.isActive});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final int sessionKey;
  final bool english;
  final bool isDarkTheme;
  final bool isActive;
  @override
  State<AdminPCWorkChatScreen> createState() => _AdminPCWorkChatScreenState();
}

class _AdminPCWorkChatScreenState extends State<AdminPCWorkChatScreen> with WidgetsBindingObserver {
  final _message = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  Timer? _threadsTimer;
  String? _token;
  String? _error;
  List<Map<String,dynamic>> _threads = [];
  List<Map<String,dynamic>> _messages = [];
  int? _selected;
  int _lastId = 0;
  bool _loading = true, _sending = false, _busy = false;
  bool _appResumed = true;
  bool get _dark => widget.isDarkTheme;
  String tr(String bg,String en) => widget.english ? en : bg;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_init();}
  void _scrollToLatest(){WidgetsBinding.instance.addPostFrameCallback((_){if(!_scroll.hasClients)return;_scroll.jumpTo(_scroll.position.maxScrollExtent);Future<void>.delayed(const Duration(milliseconds:100),(){if(mounted&&_scroll.hasClients)_scroll.jumpTo(_scroll.position.maxScrollExtent);});});}
  @override void didChangeMetrics(){if(widget.isActive)_scrollToLatest();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){final resumed=state==AppLifecycleState.resumed;if(_appResumed==resumed)return;_appResumed=resumed;if(!resumed){_timer?.cancel();_threadsTimer?.cancel();_timer=null;_threadsTimer=null;}else if(widget.isActive){_start();unawaited(_refresh());}}
  Future<void> _init() async { try { _token=await widget.tokenProvider(); if(_token==null||_token!.isEmpty) throw Exception(tr('Необходим е администраторски вход.','Administrator sign-in required.')); await _loadThreads(); if(widget.isActive)_start(); } catch(e){if(mounted)setState((){_error='$e';_loading=false;});} }
  void _start(){_timer?.cancel();_threadsTimer?.cancel();_timer=null;_threadsTimer=null;if(widget.isActive&&_appResumed&&_token!=null){_timer=Timer.periodic(const Duration(seconds:6),(_){if(!_busy&&!_sending)unawaited(_loadMessages());});_threadsTimer=Timer.periodic(const Duration(seconds:30),(_){if(!_sending)unawaited(_loadThreads());});}}
  @override void didUpdateWidget(covariant AdminPCWorkChatScreen old){super.didUpdateWidget(old);if(old.sessionKey!=widget.sessionKey){_timer?.cancel();_threadsTimer?.cancel();_token=null;_threads=[];_messages=[];_selected=null;_lastId=0;_loading=true;_init();}else if(old.isActive!=widget.isActive){_start();if(widget.isActive&&_appResumed){_scrollToLatest();unawaited(_refresh());}}}
  Future<void> _loadThreads() async {final t=_token;if(t==null)return;final rows=await widget.api.getAdminChatThreads(t);if(!mounted)return;setState((){_threads=rows;_loading=false;_error=null;});if(_selected==null&&rows.isNotEmpty)await _select(int.tryParse('${rows.first['user_id']}')??0);}
  Future<void> _select(int id) async {if(id<=0||_token==null)return;setState((){_selected=id;_messages=[];_lastId=0;_loading=true;});await _loadMessages(initial:true);}
  Future<void> _loadMessages({bool initial=false}) async {final t=_token, id=_selected;if(t==null||id==null||_busy)return;_busy=true;try{final result=await widget.api.getAdminChatMessages(t,id,afterId:_lastId);final rows=(result['messages'] as List? ?? const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();if(!mounted)return;if(rows.isNotEmpty){setState((){_messages.addAll(rows);for(final row in rows){final n=int.tryParse('${row['id']}')??0;if(n>_lastId)_lastId=n;}});_scrollToLatest();}if(initial&&mounted)setState(()=>_loading=false);}catch(e){if(mounted){setState(()=>_error='$e');if(initial)setState(()=>_loading=false);}}finally{_busy=false;}}
  Future<void> _refresh() async {try{await _loadThreads();if(_selected!=null){await _loadMessages();}}catch(_){}}
  Future<void> _send() async {final text=_message.text.trim();final t=_token;final id=_selected;if(text.isEmpty||t==null||id==null||_sending)return;setState(()=>_sending=true);try{await widget.api.sendAdminChatMessage(t,id,text);_message.clear();await _loadMessages();await _loadThreads();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}finally{if(mounted)setState(()=>_sending=false);}}
  @override void dispose(){_timer?.cancel();_threadsTimer?.cancel();WidgetsBinding.instance.removeObserver(this);_message.dispose();_scroll.dispose();super.dispose();}
  @override Widget build(BuildContext context){final fg=_dark?Colors.white:const Color(0xFF172033);final muted=_dark?Colors.white60:Colors.black54;return Column(children:[
    SizedBox(height:76,child:_loading&&_threads.isEmpty?const Center(child:CircularProgressIndicator()):ListView.separated(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),itemCount:_threads.length,itemBuilder:(context,i){final row=_threads[i];final id=int.tryParse('${row['user_id']}')??0;final active=id==_selected;final name=(row['display_name']??row['email']??tr('Клиент','Customer')).toString();final unread=int.tryParse('${row['unread_count']}')??0;return InkWell(onTap:()=>_select(id),borderRadius:BorderRadius.circular(13),child:Container(width:145,padding:const EdgeInsets.all(9),decoration:BoxDecoration(color:active?const Color(0xFF164D59):(_dark?const Color(0xFF172536):Colors.white),borderRadius:BorderRadius.circular(13),border:Border.all(color:active?const Color(0xFF20CBD0):(_dark?const Color(0xFF2A3B50):const Color(0xFFE0E6ED)))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:active?Colors.white:fg,fontSize:12,fontWeight:FontWeight.w700)),const SizedBox(height:3),Text((row['last_message']??row['email']??'').toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:active?Colors.white70:muted,fontSize:10)),if(unread>0)Text('$unread ${tr('нови','new')}',style:const TextStyle(color:Color(0xFFE34E70),fontSize:10,fontWeight:FontWeight.bold))])));},separatorBuilder:(_,__)=>const SizedBox(width:7)) ),
    Expanded(child:_selected==null?Center(child:Text(tr('Няма клиентски разговори.','No customer conversations.'),style:TextStyle(color:muted))):_loading?const Center(child:CircularProgressIndicator()):ListView.builder(controller:_scroll,padding:const EdgeInsets.fromLTRB(10,5,10,5),itemCount:_messages.length,itemBuilder:(context,i){final row=_messages[i];final admin=row['sender_type']=='admin';return Align(alignment:admin?Alignment.centerRight:Alignment.centerLeft,child:Container(constraints:BoxConstraints(maxWidth:MediaQuery.of(context).size.width*.82),margin:const EdgeInsets.symmetric(vertical:3),padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),decoration:BoxDecoration(color:admin?const Color(0xFF164D59):(_dark?const Color(0xFF1A2738):Colors.white),borderRadius:BorderRadius.circular(14),border:Border.all(color:_dark?const Color(0xFF2A3B50):const Color(0xFFE0E6ED))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text((row['message']??'').toString(),style:TextStyle(color:admin||_dark?Colors.white:fg)),const SizedBox(height:3),Text((row['created_at']??'').toString(),style:TextStyle(fontSize:9,color:admin||_dark?Colors.white60:muted))]))); })),
    if(_error!=null)Padding(padding:const EdgeInsets.all(4),child:Text(_error!,style:const TextStyle(color:Colors.orange,fontSize:11))),
    Padding(padding:EdgeInsets.fromLTRB(7,2,7,MediaQuery.of(context).viewInsets.bottom>0?0:1),child:Row(children:[Expanded(child:TextField(controller:_message,minLines:1,maxLines:3,keyboardType:TextInputType.multiline,textInputAction:TextInputAction.send,textCapitalization:TextCapitalization.sentences,decoration:InputDecoration(isDense:true,hintText:tr('Отговори на клиента…','Reply to customer…'),contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:7)),onSubmitted:(_)=>_send())),const SizedBox(width:6),IconButton.filled(onPressed:_sending?null:_send,icon:_sending?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.send_rounded,size:18))]))
  ]);}
}
