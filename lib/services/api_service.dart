import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:jellyflix/models/user.dart';
import 'package:flutter/material.dart';
import 'package:openapi/openapi.dart';
import 'package:built_collection/built_collection.dart';

class ApiService {
  Openapi? _jellyfinApi;
  String? _baseUrl;
  User? _user;
  Map<String, String> headers = {
    "Accept": "application/json",
    "Accept-Language": "en-US,en;q=0.5",
    "Accept-Encoding": "gzip, deflate",
    "Authorization":
        "MediaBrowser Client=\"AnotherJellyfinClient\", Device=\"notset\", DeviceId=\"Unknown Device Id\", Version=\"10.8.11\"",
    "Content-Type": "application/json",
    "Connection": "keep-alive",
  };

  build() {
    return ApiService();
  }

  login(String baseUrl, String username, String pw) async {
    // TODO add error handling
    _jellyfinApi = Openapi(basePathOverride: baseUrl);
    var response = await _jellyfinApi!.getUserApi().authenticateUserByName(
        authenticateUserByNameRequest: AuthenticateUserByNameRequest((b) => b
          ..username = username
          ..pw = pw),
        headers: headers);

    headers["Authorization"] =
        "${headers["Authorization"]!}, Token=\"${response.data!.accessToken!}\"";
    headers["Origin"] = baseUrl;
    _baseUrl = baseUrl;
    _user = User(
      id: response.data!.user!.id,
      name: response.data!.user!.name,
    );
  }

  Future<BaseItemDto> getItemDetails(String id) async {
    var response = await _jellyfinApi!.getUserLibraryApi().getItem(
          userId: _user!.id!,
          itemId: id,
          headers: headers,
        );
    return response.data!;
  }

  CachedNetworkImage? getImage(
      {required String id, required ImageType type, String? blurHash}) {
    String url = "$_baseUrl/Items/$id/Images/${type.name}";

    return CachedNetworkImage(
      width: double.infinity,
      imageUrl: url,
      httpHeaders: headers,
      fit: BoxFit.cover,
      placeholder: blurHash == null
          ? null
          : (context, url) {
              return BlurHash(
                hash: blurHash,
                imageFit: BoxFit.cover,
              );
            },
      errorWidget: (context, url, error) {
        return const SizedBox();
      },
      errorListener: (value) {
        //! Errors can't be caught right now
        //! There is a pr to fix this: https://github.com/Baseflow/flutter_cached_network_image/pull/777
      },
    );
  }

  Future<List<BaseItemDto>> getContinueWatching() async {
    var response = await _jellyfinApi!
        .getItemsApi()
        .getResumeItems(userId: _user!.id!, headers: headers);
    return response.data!.items!.toList();
  }

  Future<List<BaseItemDto>> getLatestItems(String collectionType) async {
    List<BaseItemDto> items = [];
    var folders = await getMediaFolders();
    // get all movie collections and their ids
    var movieCollections = folders.where((element) {
      return element.collectionType == collectionType;
    }).toList();
    var movieCollectionIds = movieCollections.map((e) {
      return e.id!;
    }).toList();

    for (var id in movieCollectionIds) {
      var response = await _jellyfinApi!.getUserLibraryApi().getLatestMedia(
          userId: _user!.id!,
          parentId: id,
          headers: headers,
          fields: BuiltList<ItemFields>(ItemFields.values));

      // add response to list
      items.addAll(response.data!);
    }
    return items;
  }

  Future<List<BaseItemDto>> getMediaFolders() async {
    var response = await _jellyfinApi!
        .getUserViewsApi()
        .getUserViews(userId: _user!.id!, headers: headers);
    //keep only video folders
    var folders = response.data!.items!.where((element) {
      return element.collectionType == "movies" ||
          element.collectionType == "tvshows";
    }).toList();
    return folders;
    //return response.data!;
  }

  Future getEpisodes(String id) async {
    var response = await _jellyfinApi!
        .getTvShowsApi()
        .getEpisodes(userId: _user!.id!, seriesId: id, headers: headers);
    return response.data!;
  }

  getStreamUrl(String itemId) {
    if (_baseUrl == null) {
      throw Exception("Not logged in");
    } else {
      return "$_baseUrl/videos/$itemId/master.m3u8?MediaSourceId=$itemId";
    }
  }

  Future<List<BaseItemDto>> getFilterItems(
      {List<BaseItemDto>? genreIds, String? searchTerm}) async {
    var folders = await getMediaFolders();
    var ids = genreIds == null
        ? null
        : BuiltList<String>.from(genreIds.map((e) => e.id!));
    List<BaseItemDto> items = [];
    for (var folder in folders) {
      var response = await _jellyfinApi!.getItemsApi().getItems(
            userId: _user!.id!,
            headers: headers,
            parentId: folder.id,
            genreIds: ids,
            searchTerm: searchTerm,
            recursive: true,
            includeItemTypes: BuiltList<BaseItemKind>([
              BaseItemKind.movie,
              BaseItemKind.series,
              BaseItemKind.episode,
              BaseItemKind.boxSet
            ]),
          );
      items.addAll(response.data!.items!);
    }
    return items;
  }

  Future<List<BaseItemDto>> getGenres() async {
    List<BaseItemDto> genres = [];
    var folders = await getMediaFolders();
    for (var folder in folders) {
      var response = await _jellyfinApi!
          .getGenresApi()
          .getGenres(userId: _user!.id!, headers: headers, parentId: folder.id);
      genres.addAll(response.data!.items!);
    }
    // keep only unique genres
    genres = genres.toSet().toList();
    return genres;
  }
}
