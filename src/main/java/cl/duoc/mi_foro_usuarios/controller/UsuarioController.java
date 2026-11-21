package cl.duoc.mi_foro_usuarios.controller;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import cl.duoc.mi_foro_usuarios.dto.UsuarioRequestDTO;
import cl.duoc.mi_foro_usuarios.dto.UsuarioRequestOptionalDTO;
import cl.duoc.mi_foro_usuarios.dto.UsuarioResponseDTO;
import cl.duoc.mi_foro_usuarios.service.ApiResponse;
import cl.duoc.mi_foro_usuarios.service.UsuarioService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;

@RestController 
@RequestMapping ("api/mi-foro/usuarios")
public class UsuarioController {

    private final UsuarioService service;

    public UsuarioController(UsuarioService service) {
        this.service = service;
    }


    // get
    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping
    public ResponseEntity<?> getUsuarios() {
        ApiResponse<List<UsuarioResponseDTO>> r = service.getUsuarios();
        return ResponseEntity.status(r.getEstado()).body(r.getRespuesta());
    }


    // get id
    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping("/{id}")
    public ResponseEntity<?> getUsuario(@PathVariable Long id) {
        ApiResponse<?> r = service.getUsuarioById(id);
        return ResponseEntity.status(r.getEstado()).body(r.getRespuesta());
    }


    // post
    @PostMapping 
    public ResponseEntity<?> doUsuario(@Valid @RequestBody UsuarioRequestDTO request) {
        ApiResponse<?> r = service.doUsuario(request);
        return ResponseEntity.status(r.getEstado()).body(r.getRespuesta());
    }


    // put
    @PutMapping("/{id}")
    public ResponseEntity<?> setUsuario(
        @PathVariable Long id,
        @Valid @RequestBody UsuarioRequestOptionalDTO request,
        HttpServletRequest httpRequest
    ) {
        ApiResponse<?> r = service.setUsuario(id, request, httpRequest);
        return ResponseEntity.status(r.getEstado()).body(r.getRespuesta());
    }


    // delete
    @PreAuthorize("hasRole('ADMIN')")
    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteUsuario(@PathVariable Long id) {
        ApiResponse<?> r = service.deletedUsuario(id);
        return ResponseEntity.status(r.getEstado()).body(r.getRespuesta());
    }

}

